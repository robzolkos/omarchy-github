import QtQuick
import Omarchy.PluginPresentation 1.0

// GitHub dashboard data service. GitHubApi owns authority-free API orchestration;
// this item schedules it and exposes one stable, defensive model to the panel.
Item {
    id: root

    property var settings: ({
    })
    property bool loading: false
    property string state: "loading"
    property string message: "Loading GitHub…"
    property string login: ""
    property string fetchedRepositoryScope: "owned"
    property string fetchedAt: ""
    property var notifications: []
    property int notificationsRevision: 0
    property var reviewRequests: []
    property var assignedIssues: []
    property var myPullRequests: []
    property int myPullRequestsTotal: 0
    property var actions: []
    property var failedActions: []
    property var repositories: []
    property var navigationHandles: ({})
    property var warnings: []
    property var rateLimit: null
    property bool refreshQueued: false
    property string markingNotificationId: ""
    property bool markingAllNotifications: false
    property var markingAllNotificationIds: []
    property string notificationActionStatus: ""
    // Thread IDs waiting for PATCH after GitHub confirmed them locally. An
    // in-flight refresh must not restore these rows, or the bar stays lit until
    // the next poll even though the user already opened or marked the thread.
    property var hiddenNotifications: ({})
    property var markQueue: []
    // Single-thread and bulk marking share one serialized path, so the panel gates every
    // entry point on this rather than on whichever flag a given call happens to
    // set. A caller added later inherits the guard instead of having to know.
    readonly property bool marking: markingNotificationId !== "" || markingAllNotifications
    readonly property bool canMarkRead: runtime.hasPermission("bash.execute", "run")
    readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 900, 60, 3600)
    readonly property int unreadCount: notifications.length
    readonly property int actionCount: actions.length
    // A broken check on your own pull request is the kind of thing the bar icon
    // exists to surface, so it counts toward the alarming state. Drafts are
    // excluded: a red check on work you have not offered up yet is expected,
    // and it would leave the icon permanently lit.
    readonly property int failingPullRequestCount: myPullRequests.filter(function(item) {
        return !item.draft && root.isBrokenCheck(item.checks);
    }).length
    readonly property bool iconAlwaysUnlit: boolSetting("iconAlwaysUnlit", false)
    // An unrecognised value falls back to the web app window rather than the
    // browser, so a stale entry cannot silently revert the default behaviour.
    readonly property string linkBehavior: String(setting("linkBehavior", "Web app window")).toLowerCase() === "browser tab" ? "Browser tab" : "Web app window"
    readonly property bool alarming: !iconAlwaysUnlit && (unreadCount > 0 || actionCount > 0 || reviewRequests.length > 0 || failingPullRequestCount > 0)

    // StatusCheckRollup groupings live here so the alarming count, the row label
    // and the row glyph cannot drift apart when a state is reclassified.
    function isBrokenCheck(checks) {
        var value = String(checks || "");
        return value === "FAILURE" || value === "ERROR";
    }

    function isRunningCheck(checks) {
        var value = String(checks || "");
        return value === "PENDING" || value === "EXPECTED";
    }

    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    function intSetting(name, fallback, minimum, maximum) {
        var value = parseInt(String(setting(name, fallback)), 10);
        if (!isFinite(value))
            value = fallback;

        return Math.max(minimum, Math.min(maximum, value));
    }

    function boolSetting(name, fallback) {
        var value = setting(name, fallback);
        if (value === true || value === false)
            return value;

        var text = String(value).toLowerCase();
        return text === "true" || text === "yes" || text === "on" || text === "1";
    }

    // Matched against the known options rather than by substring, so an option
    // added later falls back to the narrower scope instead of silently widening
    // it. `fetchedRepositoryScope` reports what the last payload contained.
    function repositoryMode() {
        return String(setting("repositoryScope", "Owned")).toLowerCase() === "owned and organizations" ? "organizations" : "owned";
    }

    function actionMode() {
        var value = String(setting("actionScanBehavior", "Recent repositories")).toLowerCase();
        if (value === "off")
            return "off";

        if (value === "all repositories")
            return "all";

        return "recent";
    }

    function refreshOptions() {
        return {
            includeArchived: boolSetting("includeArchived", false),
            includeForks: boolSetting("includeForks", false),
            repositoryScope: repositoryMode(),
            includeArchivedReviews: boolSetting("includeArchivedReviewRequests", false),
            includeDraftReviews: boolSetting("includeDraftReviewRequests", false),
            actionScan: actionMode(),
            actionRepoLimit: intSetting("actionScanRepoLimit", 15, 5, 200),
            actionConcurrency: intSetting("actionScanConcurrency", 6, 1, 12),
            failedDays: intSetting("failedActionDays", 7, 1, 30),
            failedLimit: intSetting("failedActionLimit", 20, 1, 100)
        };
    }

    function copyMap(value) {
        var copy = {};
        var source = value || {};
        for (var key in source)
            copy[key] = source[key];
        return copy;
    }

    function hideNotification(id) {
        var value = String(id || "");
        if (value === "")
            return ;

        var hidden = copyMap(hiddenNotifications);
        var next = [];
        var found = false;
        for (var i = 0; i < notifications.length; i++) {
            var item = notifications[i];
            if (String(item.id || "") === value) {
                hidden[value] = item;
                found = true;
            } else {
                next.push(item);
            }
        }
        if (!found && hidden[value] === undefined)
            hidden[value] = {id: value};

        hiddenNotifications = hidden;
        if (found) {
            notifications = next;
            notificationsRevision++;
        }
    }

    function restoreHiddenNotification(id) {
        var value = String(id || "");
        var item = hiddenNotifications[value];
        var hidden = copyMap(hiddenNotifications);
        delete hidden[value];
        hiddenNotifications = hidden;
        if (!item)
            return ;

        for (var i = 0; i < notifications.length; i++) {
            if (String(notifications[i].id || "") === value)
                return ;
        }
        notifications = [item].concat(notifications);
        notificationsRevision++;
    }

    function hideAllNotifications() {
        var ids = [];
        var hidden = copyMap(hiddenNotifications);
        var remaining = [];
        for (var i = 0; i < notifications.length; i++) {
            var item = notifications[i];
            var id = String(item.id || "");
            if (id !== "") {
                ids.push(id);
                hidden[id] = item;
            } else {
                remaining.push(item);
            }
        }
        if (ids.length > 0) {
            hiddenNotifications = hidden;
            notifications = remaining;
            notificationsRevision++;
        }
        return ids;
    }

    function restoreHiddenNotifications(ids) {
        var values = Array.isArray(ids) ? ids : [];
        for (var i = values.length - 1; i >= 0; i--)
            restoreHiddenNotification(values[i]);
    }

    function visibleNotifications(rows) {
        var incoming = Array.isArray(rows) ? rows : [];
        var hidden = hiddenNotifications || {};
        var nextHidden = {};
        var visible = [];
        for (var i = 0; i < incoming.length; i++) {
            var item = incoming[i];
            var id = String(item.id || "");
            if (hidden[id])
                nextHidden[id] = item;
            else
                visible.push(item);
        }
        hiddenNotifications = nextHidden;
        return visible;
    }

    function enqueueMark(id) {
        var value = String(id || "");
        if (value === "" || markingNotificationId === value)
            return ;

        for (var i = 0; i < markQueue.length; i++) {
            if (markQueue[i] === value)
                return ;
        }
        markQueue = markQueue.concat([value]);
    }

    function startQueuedMark() {
        if (loading || marking || markQueue.length === 0)
            return false;

        var value = String(markQueue[0] || "");
        markQueue = markQueue.slice(1);
        if (value === "")
            return startQueuedMark();

        actionStatusTimer.stop();
        markingNotificationId = value;
        notificationActionStatus = "Marking notification read…";
        githubApi.markNotification(value, function(ok, resultMessage) {
            root.finishMark(ok, resultMessage);
        });
        return true;
    }

    function refresh() {
        if (loading || marking || markQueue.length > 0) {
            refreshQueued = true;
            return ;
        }
        refreshQueued = false;
        loading = true;
        if (!githubApi.refresh(refreshOptions(), function(data) {
            root.loading = false;
            root.apply(data);
            if (root.startQueuedMark())
                return;
            if (root.refreshQueued) {
                root.refreshQueued = false;
                Qt.callLater(root.refresh);
            }
        })) {
            loading = false;
            state = "error";
            message = "A GitHub refresh is already running.";
        }
    }

    function apply(raw) {
        try {
            var data = typeof raw === "string" ? JSON.parse(String(raw || "")) : (raw || {});
            state = String(data.state || "error");
            message = String(data.message || "");
            login = String(data.login || "");
            fetchedRepositoryScope = String(data.repositoryScope || "owned");
            fetchedAt = String(data.fetchedAt || "");
            notifications = visibleNotifications(data.notifications);
            notificationsRevision++;
            reviewRequests = Array.isArray(data.reviewRequests) ? data.reviewRequests : [];
            assignedIssues = Array.isArray(data.assignedIssues) ? data.assignedIssues : [];
            myPullRequests = Array.isArray(data.myPullRequests) ? data.myPullRequests : [];
            myPullRequestsTotal = Number(data.myPullRequestsTotal) || myPullRequests.length;
            actions = Array.isArray(data.actions) ? data.actions : [];
            failedActions = Array.isArray(data.failedActions) ? data.failedActions : [];
            repositories = Array.isArray(data.repositories) ? data.repositories : [];
            navigationHandles = data.navigationHandles && typeof data.navigationHandles === "object" ? data.navigationHandles : ({});
            warnings = Array.isArray(data.warnings) ? data.warnings : [];
            rateLimit = data.rateLimit || null;
        } catch (error) {
            state = "error";
            message = "GitHub returned an unreadable response.";
            warnings = [String(error)];
        }
    }

    function markNotificationRead(id) {
        var value = String(id || "");
        if (value === "" || !canMarkRead)
            return ;

        // Drop the row before GitHub round-trips. Opening a thread while a
        // refresh is already running used to no-op, so the icon stayed alarming
        // until the next poll even after the user had seen the notification.
        hideNotification(value);
        enqueueMark(value);
        startQueuedMark();
    }

    function canonicalNotificationTimestamp(value) {
        var text = String(value || "");
        if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(text))
            return "";

        var milliseconds = Date.parse(text);
        if (!isFinite(milliseconds) || new Date(milliseconds).toISOString().replace(".000Z", "Z") !== text)
            return "";

        return milliseconds <= Date.now() ? text : "";
    }

    // Capture the exact displayed boundary on the first click. The panel binds
    // confirmation to notificationsRevision, so any refresh invalidates this
    // prepared value before the destructive second click can run.
    function prepareMarkAllNotificationsRead() {
        if (!canMarkRead || notifications.length === 0 || loading || marking)
            return "";

        var boundary = "";
        for (var i = 0; i < notifications.length; i++) {
            var updated = canonicalNotificationTimestamp(notifications[i].updatedAt);
            if (updated === "") {
                notificationActionStatus = "Refresh before marking everything read.";
                actionStatusTimer.restart();
                return "";
            }
            if (updated > boundary)
                boundary = updated;
        }

        var boundaryIds = [];
        for (var j = 0; j < notifications.length; j++) {
            if (String(notifications[j].updatedAt || "") !== boundary)
                continue;
            var id = String(notifications[j].id || "");
            if (!/^\d+$/.test(id)) {
                notificationActionStatus = "Refresh before marking everything read.";
                actionStatusTimer.restart();
                return "";
            }
            boundaryIds.push(id);
        }
        return JSON.stringify({boundary: boundary, boundaryIds: boundaryIds, revision: notificationsRevision});
    }

    function markAllNotificationsRead(prepared) {
        var confirmed = String(prepared || "");
        if (confirmed === "" || loading || marking)
            return ;

        // Recompute immediately before starting. This protects non-panel callers
        // as well as the panel's revision-bound confirmation.
        if (confirmed !== prepareMarkAllNotificationsRead()) {
            notificationActionStatus = "Notifications changed. Confirm again.";
            actionStatusTimer.restart();
            return ;
        }

        var snapshot;
        try {
            snapshot = JSON.parse(confirmed);
        } catch (error) {
            notificationActionStatus = "Refresh before marking everything read.";
            actionStatusTimer.restart();
            return ;
        }

        actionStatusTimer.stop();
        markingAllNotifications = true;
        markingAllNotificationIds = hideAllNotifications();
        notificationActionStatus = "Marking all notifications read…";
        githubApi.markAll(String(snapshot.boundary || ""), snapshot.boundaryIds, function(ok, resultMessage) {
            root.finishMark(ok, resultMessage);
        });
    }

    function finishMark(ok, resultMessage) {
        var all = markingAllNotifications;
        var markedId = markingNotificationId;
        if (ok) {
            notificationActionStatus = all ? "Notifications marked read. Refreshing…" : "Notification marked read. Refreshing…";
        } else {
            var fallback = all ? "Could not mark all notifications read." : "Could not mark notification read.";
            notificationActionStatus = String(resultMessage || fallback);
            if (all)
                restoreHiddenNotifications(markingAllNotificationIds);
            else if (markedId !== "")
                restoreHiddenNotification(markedId);
        }
        markingNotificationId = "";
        markingAllNotifications = false;
        markingAllNotificationIds = [];
        actionStatusTimer.restart();
        if (startQueuedMark())
            return;

        // GitHub is authoritative after every attempt. This reconciles
        // successful, failed, and partially completed bulk operations.
        refreshQueued = false;
        Qt.callLater(refresh);
    }

    visible: false

    Timer {
        interval: root.refreshIntervalSec * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: actionStatusTimer

        interval: 3000
        repeat: false
        onTriggered: root.notificationActionStatus = ""
    }

    GitHubApi {
        id: githubApi
    }

}
