using CrestCore.Application;

namespace CrestCore.Contracts;

/// The eight most recently used tabs of the Space this window shows. The
/// current tab leads, and equal activation times retain the Space's order.
public sealed record RecentTabCandidates(Guid WindowId) : Query<RecentTabList> {
    #region Actions - Answering

    internal override RecentTabList Answer(CrestApp app) {
        var window = app.Device.Opened(WindowId);
        var authority = app.Device.Workspace(window.WorkspaceId);
        Guid spaceId;
        Guid? shown;
        lock (app.Device.Gate) {
            spaceId = window.ShownSpaceId;
            shown = window.Tab(spaceId);
        }
        if (Device.Available(authority.Current, spaceId) is not { } space || authority.IsLocked(space))
            return new(WindowId, spaceId, Guid.Empty, shown, []);
        return new(WindowId, spaceId, space.ProfileId, shown,
            [.. space.Tabs.OrderByDescending(tab => tab.Id == shown).ThenByDescending(tab => tab.LastActivatedAt)
                .Take(8).Select(tab => tab.Id)]);
    }

    #endregion
}
