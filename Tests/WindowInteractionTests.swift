import XCTest
import ApplicationServices
@testable import MacMiddleCore

final class MiddleClickSequenceTests: XCTestCase {
    func testSuccessfulMinimizeConsumesEntireSequenceOnlyOnce() {
        var sequence = MiddleClickSequence()
        var attempts = 0
        let minimize = { attempts += 1; return true }
        XCTAssertTrue(sequence.consume(.otherMouseDown, button: 2, minimize: minimize))
        XCTAssertTrue(sequence.consume(.otherMouseDragged, button: 2, minimize: minimize))
        XCTAssertTrue(sequence.consume(.otherMouseDragged, button: 2, minimize: minimize))
        XCTAssertTrue(sequence.consume(.otherMouseUp, button: 2, minimize: minimize))
        XCTAssertFalse(sequence.consume(.otherMouseUp, button: 2, minimize: minimize))
        XCTAssertEqual(attempts, 1)
    }

    func testFailedMinimizePassesThroughEntireSequence() {
        var sequence = MiddleClickSequence()
        XCTAssertFalse(sequence.consume(.otherMouseDown, button: 2) { false })
        XCTAssertFalse(sequence.consume(.otherMouseDragged, button: 2) { XCTFail("Unexpected minimize"); return true })
        XCTAssertFalse(sequence.consume(.otherMouseUp, button: 2) { XCTFail("Unexpected minimize"); return true })
    }

    func testOtherButtonsDoNotMinimizeOrInterruptSwallowedMiddleClick() {
        var sequence = MiddleClickSequence()
        XCTAssertTrue(sequence.consume(.otherMouseDown, button: 2) { true })
        for button: Int64 in [0, 1, 3, 4] {
            for type: CGEventType in [.otherMouseDown, .otherMouseDragged, .otherMouseUp] {
                XCTAssertFalse(sequence.consume(type, button: button) { XCTFail("Other button minimized"); return true })
            }
        }
        XCTAssertTrue(sequence.consume(.otherMouseUp, button: 2) { false })
    }

    func testOrphanDragAndReleasePassThrough() {
        var sequence = MiddleClickSequence()
        for type: CGEventType in [.otherMouseDragged, .otherMouseUp] {
            XCTAssertFalse(sequence.consume(type, button: 2) { XCTFail("Unexpected minimize"); return true })
        }
    }

    func testResetClearsSuppressionForStopAndTapRecovery() {
        var sequence = MiddleClickSequence()
        XCTAssertTrue(sequence.consume(.otherMouseDown, button: 2) { true })
        sequence.reset()
        XCTAssertFalse(sequence.consume(.otherMouseDragged, button: 2) { false })
        XCTAssertFalse(sequence.consume(.otherMouseUp, button: 2) { false })
        XCTAssertTrue(sequence.consume(.otherMouseDown, button: 2) { true })
    }

    func testNewDownReplacesStaleSuppression() {
        var sequence = MiddleClickSequence()
        XCTAssertTrue(sequence.consume(.otherMouseDown, button: 2) { true })
        XCTAssertFalse(sequence.consume(.otherMouseDown, button: 2) { false })
        XCTAssertFalse(sequence.consume(.otherMouseUp, button: 2) { true })
    }
}

private final class Node {
    var role: String?
    var parent: Node?
    var frame: CGRect?
    var button: Node?
    var enabled: Bool? = true
    var fullScreen: Bool? = false

    init(_ role: String?, parent: Node? = nil, frame: CGRect? = nil) {
        self.role = role
        self.parent = parent
        self.frame = frame
    }
}

private final class FakeAccessibility: WindowAccessibility {
    var pressed: [Node] = []
    var pressSucceeds = true
    var roleReads = 0
    func role(_ element: Node) -> String? { roleReads += 1; return element.role }
    func parent(_ element: Node) -> Node? { element.parent }
    func frame(_ element: Node) -> CGRect? { element.frame }
    func minimizeButton(_ window: Node) -> Node? { window.button }
    func enabled(_ element: Node) -> Bool? { element.enabled }
    func fullScreen(_ window: Node) -> Bool? { window.fullScreen }
    func press(_ element: Node) -> Bool { pressed.append(element); return pressSucceeds }
}

final class TitleBarDetectorTests: XCTestCase {
    private var access: FakeAccessibility!
    private var window: Node!
    private var button: Node!
    private let titlePoint = CGPoint(x: 400, y: 115)

    override func setUp() {
        access = FakeAccessibility()
        window = Node(kAXWindowRole, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        button = Node(kAXButtonRole, parent: window, frame: CGRect(x: 130, y: 110, width: 12, height: 12))
        window.button = button
    }

    private func minimize(_ hit: Node? = nil, at point: CGPoint? = nil) -> Bool {
        TitleBarDetector(access: access).minimize(hit: hit ?? window, at: point ?? titlePoint)
    }

    func testEmptyTitleBarMinimizesHitWindow() {
        XCTAssertTrue(minimize())
        XCTAssertTrue(access.pressed.first === button)
    }

    func testTitleTextInsideNoninteractiveContainersIsAccepted() {
        let toolbar = Node(kAXToolbarRole, parent: window)
        let group = Node(kAXGroupRole, parent: toolbar)
        XCTAssertTrue(minimize(Node(kAXStaticTextRole, parent: group)))
    }

    func testControlsTabsAndContentAreRejectedEvenWithinTitleStrip() {
        for role in [kAXButtonRole, kAXRadioButtonRole, kAXTabGroupRole, kAXTextFieldRole,
                     kAXTextAreaRole, kAXScrollAreaRole, "AXWebArea", "AXUnknown"] {
            XCTAssertFalse(minimize(Node(role, parent: window)), role)
        }
        XCTAssertTrue(access.pressed.isEmpty)
    }

    func testTitleTextInsideInteractiveAncestorIsRejected() {
        let tab = Node(kAXRadioButtonRole, parent: window)
        XCTAssertFalse(minimize(Node(kAXStaticTextRole, parent: tab)))
        XCTAssertTrue(access.pressed.isEmpty)
    }

    func testContentAndPointsOutsideWindowWidthAreRejected() {
        for point in [CGPoint(x: 400, y: 200), CGPoint(x: 400, y: 104),
                      CGPoint(x: 400, y: 128), CGPoint(x: 99, y: 115), CGPoint(x: 901, y: 115)] {
            XCTAssertFalse(minimize(at: point), "Unexpected minimize at \(point)")
        }
        XCTAssertTrue(access.pressed.isEmpty)
    }

    func testStripTracksWindowAndTrafficLightPositionOnOtherDisplays() {
        window.frame = CGRect(x: -1000, y: -500, width: 800, height: 600)
        button.frame = CGRect(x: -970, y: -470, width: 12, height: 12)
        XCTAssertTrue(minimize(at: CGPoint(x: -600, y: -465)))
        XCTAssertFalse(minimize(at: CGPoint(x: -600, y: -490)))
    }

    func testStripDoesNotStartAboveWindow() {
        button.frame = CGRect(x: 130, y: 101, width: 12, height: 12)
        XCTAssertFalse(minimize(at: CGPoint(x: 400, y: 99)))
        XCTAssertTrue(minimize(at: CGPoint(x: 400, y: 101)))
    }

    func testFullScreenWindowIsExcluded() {
        window.fullScreen = true
        XCTAssertFalse(minimize())
        XCTAssertTrue(access.pressed.isEmpty)
    }

    func testMissingOptionalFullScreenAttributeRetainsExistingBehavior() {
        window.fullScreen = nil
        XCTAssertTrue(minimize())
    }

    func testDisabledOrUnknownMinimizeControlIsExcluded() {
        for enabled: Bool? in [false, nil] {
            button.enabled = enabled
            XCTAssertFalse(minimize())
        }
        XCTAssertTrue(access.pressed.isEmpty)
    }

    func testMissingMinimizeControlIsExcluded() {
        window.button = nil
        XCTAssertFalse(minimize())
        XCTAssertTrue(access.pressed.isEmpty)
    }

    func testMissingFramesAreExcluded() {
        let savedFrame = window.frame
        window.frame = nil
        XCTAssertFalse(minimize())
        window.frame = savedFrame
        button.frame = nil
        XCTAssertFalse(minimize())
        XCTAssertTrue(access.pressed.isEmpty)
    }

    func testMissingRoleOrParentIsExcluded() {
        XCTAssertFalse(minimize(Node(nil, parent: window)))
        XCTAssertFalse(minimize(Node(kAXStaticTextRole)))
        XCTAssertTrue(access.pressed.isEmpty)
    }

    func testFailedPressDoesNotConsumeClick() {
        access.pressSucceeds = false
        var sequence = MiddleClickSequence()
        XCTAssertFalse(sequence.consume(.otherMouseDown, button: 2) { self.minimize() })
        XCTAssertEqual(access.pressed.count, 1)
        XCTAssertFalse(sequence.consume(.otherMouseUp, button: 2) { true })
    }

    func testBackgroundHitUsesItsOwnWindowNotAnotherWindow() {
        let background = Node(kAXWindowRole, frame: window.frame)
        let backgroundButton = Node(kAXButtonRole, frame: button.frame)
        background.button = backgroundButton
        XCTAssertTrue(minimize(Node(kAXStaticTextRole, parent: background)))
        XCTAssertTrue(access.pressed.first === backgroundButton)
        XCTAssertFalse(access.pressed.contains { $0 === button })
    }

    func testAncestorTraversalIsBoundedForCycles() {
        let cyclic = Node(kAXGroupRole)
        cyclic.parent = cyclic
        XCTAssertFalse(minimize(cyclic))
        XCTAssertEqual(access.roleReads, 16)
        XCTAssertTrue(access.pressed.isEmpty)
        cyclic.parent = nil
    }

    func testWindowAtTraversalLimitIsAcceptedButDeeperWindowIsRejected() {
        var hit = window!
        for _ in 0..<15 { hit = Node(kAXGroupRole, parent: hit) }
        XCTAssertTrue(minimize(hit))
        access.pressed.removeAll()
        XCTAssertFalse(minimize(Node(kAXGroupRole, parent: hit)))
        XCTAssertTrue(access.pressed.isEmpty)
    }
}
