import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserTabSwitcherTests: XCTestCase {
    // MARK: - Actions - Switching

    func testCyclingKeepsTheCapturedOrderAndSelectsOnlyOnCommit() throws {
        let (browser, space, tabs) = fixture()
        let model = BrowserTabSwitcherModel()
        var selections = 0
        XCTAssertTrue(model.begin(in: browser, reversed: false) { selections += 1 })
        XCTAssertEqual(model.highlightedTabID, tabs[1].id)
        XCTAssertEqual(browser.shownTab?.id, tabs[0].id)
        let used = try XCTUnwrap(browser.shownTab?.lastActivatedAt)
        model.advance(reversed: false)
        XCTAssertEqual(model.highlightedTabID, tabs[2].id)
        model.advance(reversed: true)
        XCTAssertEqual(model.highlightedTabID, tabs[1].id)
        XCTAssertEqual(browser.shownTab?.lastActivatedAt, used)
        XCTAssertEqual(selections, 0)
        model.commit()
        XCTAssertEqual(browser.selectedSpaceID, space.id)
        XCTAssertEqual(browser.shownTab?.id, tabs[1].id)
        XCTAssertEqual(selections, 1)
        XCTAssertFalse(model.isPresented)
        model.commit()
        XCTAssertEqual(selections, 1)
    }

    func testReverseWrapCancellationAndStaleSourceNeverSelectAnotherTab() {
        let (browser, _, tabs) = fixture()
        let model = BrowserTabSwitcherModel()
        XCTAssertTrue(model.begin(in: browser, reversed: true) { XCTFail("Cancelled gesture selected a tab") })
        XCTAssertEqual(model.highlightedTabID, tabs[2].id)
        model.advance(reversed: false)
        XCTAssertEqual(model.highlightedTabID, tabs[0].id)
        model.cancel()
        model.commit()
        XCTAssertEqual(browser.shownTab?.id, tabs[0].id)

        XCTAssertTrue(model.begin(in: browser, reversed: false) { XCTFail("Stale gesture selected a tab") })
        browser.selectTab(tabs[2].id)
        XCTAssertFalse(model.isPresented)
        model.commit()
        XCTAssertEqual(browser.shownTab?.id, tabs[2].id)
    }

    func testRemovedHighlightCancelsAndOtherRemovalsKeepTheSurvivingOrder() {
        let (browser, _, tabs) = fixture()
        let model = BrowserTabSwitcherModel()
        XCTAssertTrue(model.begin(in: browser, reversed: false) { XCTFail("Removed highlight was selected") })
        browser.deleteSessionTab(tabs[2].id, in: browser.selectedSpaceID)
        XCTAssertEqual(model.tabs.map(\.id), [tabs[0].id, tabs[1].id])
        XCTAssertEqual(model.highlightedTabID, tabs[1].id)
        browser.deleteSessionTab(tabs[1].id, in: browser.selectedSpaceID)
        XCTAssertFalse(model.isPresented)
        model.commit()
        XCTAssertEqual(browser.shownTab?.id, tabs[0].id)
    }

    func testNativeGestureRespectsCustomAssignmentsIncludingTheReverseChord() throws {
        let shortcuts = BrowserShortcutStore()
        let forward = try key(.control)
        let reverse = try key([.control, .shift])
        XCTAssertTrue(BrowserTabSwitcherKeyboardSession.begins(forward, shortcuts: shortcuts))
        XCTAssertTrue(BrowserTabSwitcherKeyboardSession.begins(reverse, shortcuts: shortcuts))
        XCTAssertTrue(
            shortcuts.assign(BrowserShortcut(key: .special(.tab), modifiers: [.control, .shift]), to: .newTab)
                is BrowserShortcutAssigned)
        XCTAssertFalse(BrowserTabSwitcherKeyboardSession.begins(reverse, shortcuts: shortcuts))
        shortcuts.clearShortcut(for: .mostRecentTab)
        XCTAssertFalse(BrowserTabSwitcherKeyboardSession.begins(forward, shortcuts: shortcuts))
        XCTAssertFalse(BrowserTabSwitcherKeyboardSession.begins(reverse, shortcuts: shortcuts))
    }

    func testNativeControlReleaseCommitsButShiftReleaseAndTabReleaseDoNot() throws {
        let (browser, _, tabs) = fixture()
        let model = BrowserTabSwitcherModel()
        let shortcuts = BrowserShortcutStore()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        XCTAssertTrue(model.begin(in: browser, reversed: false) {})
        let session = BrowserTabSwitcherKeyboardSession(model: model, window: window, shortcuts: shortcuts)
        XCTAssertFalse(session.handle(try key(.control, type: .keyUp), keyWindow: window))
        XCTAssertFalse(session.handle(try key(.control, type: .flagsChanged, code: 56), keyWindow: window))
        XCTAssertTrue(model.isPresented)
        XCTAssertEqual(browser.shownTab?.id, tabs[0].id)
        XCTAssertTrue(session.handle(try key(.control), keyWindow: window))
        XCTAssertEqual(model.highlightedTabID, tabs[2].id)
        XCTAssertFalse(session.handle(try key([], type: .flagsChanged, code: 59), keyWindow: window))
        XCTAssertEqual(browser.shownTab?.id, tabs[2].id)
        XCTAssertFalse(model.isPresented)
    }

    func testNativeEscapeAndLostWindowFocusCancelBeforeControlRelease() throws {
        let (browser, _, tabs) = fixture()
        let model = BrowserTabSwitcherModel()
        let shortcuts = BrowserShortcutStore()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        XCTAssertTrue(model.begin(in: browser, reversed: false) {})
        let session = BrowserTabSwitcherKeyboardSession(model: model, window: window, shortcuts: shortcuts)
        XCTAssertTrue(session.handle(try key(.control, code: 53), keyWindow: window))
        XCTAssertFalse(session.handle(try key([], type: .flagsChanged, code: 59), keyWindow: window))
        XCTAssertEqual(browser.shownTab?.id, tabs[0].id)
        XCTAssertTrue(model.begin(in: browser, reversed: false) {})
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(model.isPresented)
        XCTAssertFalse(session.handle(try key([], type: .flagsChanged, code: 59), keyWindow: window))
        XCTAssertEqual(browser.shownTab?.id, tabs[0].id)
        XCTAssertTrue(model.begin(in: browser, reversed: false) {})
        XCTAssertFalse(session.handle(try key([], type: .flagsChanged, code: 59), keyWindow: nil))
        XCTAssertFalse(model.isPresented)
        XCTAssertEqual(browser.shownTab?.id, tabs[0].id)
    }

    // MARK: - Actions - Fixtures

    private func fixture() -> (BrowserStore, SpaceState.Seed, [TabState.Seed]) {
        let tabs = (0..<3).map { index in
            TabState.Seed(
                title: "Tab \(index)", url: URL(string: "https://example.com/\(index)"), placement: .current,
                lastActivatedAt: Date(timeIntervalSince1970: Double(30 - index)))
        }
        let space = SpaceState.Seed(name: "Test", tabs: tabs)
        return (
            BrowserStore(seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tabs[0].id]),
            space, tabs
        )
    }

    private func key(
        _ modifiers: NSEvent.ModifierFlags, type: NSEvent.EventType = .keyDown, code: UInt16 = 48
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: code))
    }
}
