using CrestCore.Application;

namespace CrestCore.Contracts;

/// Selects a captured candidate only while the window still shows the source
/// selection in the same unlocked profile. A stale gesture changes nothing.
public sealed record CommitRecentTabSwitch(RecentTabList Source, Guid TabId) : WindowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        Window? window;
        lock (device.Gate) {
            window = device.OpenWindows.GetValueOrDefault(Source.WindowId);
            if (window is null || window.ShownSpaceId != Source.SpaceId || window.Tab(Source.SpaceId) != Source.ShownTabId)
                return;
        }
        var authority = device.Workspace(window.WorkspaceId);
        if (TabId == Source.ShownTabId || !Source.TabIds.Contains(TabId)
            || Device.Available(authority.Current, Source.SpaceId) is not { } space
            || space.ProfileId != Source.ProfileId || authority.IsLocked(space)
            || space.Tabs.All(tab => tab.Id != TabId)) return;
        new ShowTab(Source.WindowId, Source.SpaceId, TabId).Apply(device, turn);
    }

    #endregion
}
