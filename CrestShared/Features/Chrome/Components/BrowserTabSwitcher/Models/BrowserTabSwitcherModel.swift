import Foundation
import Observation

/// A window's captured candidate order. Highlighting never selects a tab or
/// updates its activation time; only committing sends an intent.
@Observable
@MainActor
final class BrowserTabSwitcherModel {
    // MARK: - Variables

    private(set) var source: RecentTabList?
    private(set) var highlightedTabID: UUID?
    @ObservationIgnored private weak var browser: BrowserStore?
    @ObservationIgnored private var didSelect: (() -> Void)?

    var tabs: [TabStateModel] {
        guard let source, let space = availableSpace else { return [] }
        return source.tabIDs.compactMap { space.tabs.model($0) }
    }

    var isPresented: Bool {
        guard let highlightedTabID else { return false }
        return tabs.contains { $0.id == highlightedTabID }
    }

    private var availableSpace: SpaceModel? {
        guard let source, let browser, browser.windowModel != nil,
            browser.selectedSpaceID == source.spaceID, browser.shownTab?.id == source.shownTabID,
            !browser.isDeleting(source.spaceID), let space = browser.shownSpace,
            space.profileID == source.profileID
        else { return nil }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard !space.settings.requiresAuthentication || browser.core.state.spaceAccess[assignment]?.isUnlocked == true
        else { return nil }
        return space
    }

    // MARK: - Actions - Switching

    @discardableResult
    func begin(in browser: BrowserStore, reversed: Bool, didSelect: @escaping () -> Void) -> Bool {
        cancel()
        guard let candidates = try? browser.core.query(RecentTabCandidates(windowID: browser.windowID)),
            candidates.tabIDs.count > (candidates.shownTabID == nil ? 0 : 1)
        else { return false }
        self.browser = browser
        self.didSelect = didSelect
        source = candidates
        let index = reversed ? candidates.tabIDs.count - 1 : (candidates.shownTabID == nil ? 0 : 1)
        highlightedTabID = candidates.tabIDs[index]
        if !isPresented { cancel() }
        return isPresented
    }

    func advance(reversed: Bool) {
        let candidates = tabs
        guard let index = candidates.firstIndex(where: { $0.id == highlightedTabID }) else {
            cancel()
            return
        }
        highlightedTabID = candidates[(index + (reversed ? candidates.count - 1 : 1)) % candidates.count].id
    }

    func commit(_ tabID: UUID? = nil) {
        let selected = tabID ?? highlightedTabID
        guard isPresented, let source, let browser, let selected,
            tabs.contains(where: { $0.id == selected })
        else {
            cancel()
            return
        }
        let didSelect = didSelect
        cancel()
        guard selected != source.shownTabID,
            browser.commitRecentTabSwitch(source, to: selected)
        else { return }
        didSelect?()
    }

    func cancel() {
        source = nil
        highlightedTabID = nil
        browser = nil
        didSelect = nil
    }
}
