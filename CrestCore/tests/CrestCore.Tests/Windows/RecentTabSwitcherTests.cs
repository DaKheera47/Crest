using System.Text.Json.Nodes;

using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    #region Actions - Recent tabs

    [Fact]
    public void RecentCandidatesAreBoundedStableAndReadOnlyWithinTheWindowsWorkspace() {
        var session = RecentTabSession();
        var spaceId = SpaceId(session["spaces"]![0]!);
        using var device = new TestDevice(session);
        var tabs = device.Authority.Current.Spaces[0].Tabs;
        var window = device.Open(spaceId, (spaceId, tabs[0].Id));
        var revision = device.Authority.Revision;
        var candidates = device.Query(new RecentTabCandidates(window));
        Assert.Equal(tabs.Take(8).Select(tab => tab.Id), candidates.TabIds);
        Assert.Equal(revision, device.Authority.Revision);

        var privateSession = RecentTabSession();
        var privateSpace = SpaceId(privateSession["spaces"]![0]!);
        var workspace = device.Attach(privateSession, WorkspaceKind.Private);
        var privateWindow = device.OpenIn(workspace, privateSpace);
        var privateCandidates = device.Query(new RecentTabCandidates(privateWindow));
        Assert.Equal(privateSpace, privateCandidates.SpaceId);
        Assert.Empty(candidates.TabIds.Intersect(privateCandidates.TabIds));

        // A tab recently used by another window cannot displace this window's current tab.
        var other = device.Open(spaceId);
        device.Send(new ShowTab(other, spaceId, tabs[9].Id));
        Assert.Equal(new[] { tabs[0].Id, tabs[9].Id }, device.Query(new RecentTabCandidates(window)).TabIds.Take(2));
    }

    [Fact]
    public void RecentSwitchCommitsOnceAndRejectsChangedSelectionsProfilesAndMissingTargets() {
        var session = RecentTabSession();
        var spaceId = SpaceId(session["spaces"]![0]!);
        using var device = new TestDevice(session);
        var tabs = device.Authority.Current.Spaces[0].Tabs;
        var window = device.Open(spaceId, (spaceId, tabs[0].Id));
        var candidates = device.Query(new RecentTabCandidates(window));
        Assert.Empty(device.Send(new CommitRecentTabSwitch(candidates with { ProfileId = Guid.NewGuid() }, tabs[1].Id)));
        Assert.Empty(device.Send(new CommitRecentTabSwitch(candidates, tabs[9].Id)));
        Assert.Empty(device.Send(new CommitRecentTabSwitch(candidates, tabs[0].Id)));
        Assert.Equal(tabs[0].Id, device.Tab(window, spaceId));

        var changes = device.Send(new CommitRecentTabSwitch(candidates, tabs[1].Id));
        Assert.Single(changes.OfType<TabsChanged>());
        Assert.Equal(tabs[1].Id, device.Tab(window, spaceId));
        Assert.Empty(device.Send(new CommitRecentTabSwitch(candidates, tabs[2].Id)));

        var fresh = device.Query(new RecentTabCandidates(window));
        device.Send(new DeleteTab(device.Workspace, window, spaceId, tabs[2].Id));
        Assert.Empty(device.Send(new CommitRecentTabSwitch(fresh, tabs[2].Id)));
        Assert.Equal(tabs[1].Id, device.Tab(window, spaceId));
        device.Send(new CloseWindow(window));
        Assert.Empty(device.Send(new CommitRecentTabSwitch(fresh, tabs[3].Id)));
    }

    [Fact]
    public void LockingASpaceWithdrawsCandidatesAndRejectsAnAlreadyCapturedSwitch() {
        var session = RecentTabSession();
        session["spaces"]![0]!["accessPolicy"] = "deviceOwnerAuthentication";
        var spaceId = SpaceId(session["spaces"]![0]!);
        using var device = new TestDevice(session);
        var tabs = device.Authority.Current.Spaces[0].Tabs;
        var window = device.Open(spaceId, (spaceId, tabs[0].Id));
        Assert.Empty(device.Query(new RecentTabCandidates(window)).TabIds);
        Unlock(device.Send, device.Workspace, spaceId);
        var candidates = device.Query(new RecentTabCandidates(window));
        Assert.NotEmpty(candidates.TabIds);
        device.Send(new LockSpace(spaceId));
        Assert.Empty(device.Query(new RecentTabCandidates(window)).TabIds);
        Assert.Empty(device.Send(new CommitRecentTabSwitch(candidates, tabs[1].Id)));
        Assert.Equal(tabs[0].Id, device.Tab(window, spaceId));
    }

    private static JsonNode RecentTabSession() {
        var session = SavedSession().Document["session"]!;
        var space = session["spaces"]![0]!;
        var template = space["tabs"]![0]!.DeepClone();
        var tabs = new JsonArray();
        for (int index = 0; index < 10; index++) {
            var tab = template.DeepClone();
            tab["id"] = SwiftId(Guid.NewGuid());
            tab["placement"] = "current";
            tab["savedURL"] = null;
            tab["folderID"] = null;
            tab["splitGroupID"] = null;
            // Equal times exercise stable tie ordering; the current tab is older.
            tab["lastActivatedAt"] = index == 0 ? 0.0 : 800000000.0;
            tabs.Add(tab);
        }
        space["tabs"] = tabs;
        space["selectedTabID"] = tabs[0]!["id"]!.DeepClone();
        return session;
    }

    #endregion
}
