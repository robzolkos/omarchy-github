import QtQuick
import Quickshell
import Quickshell.Io

// GitHub dashboard data service. The helper owns API pagination and aggregation;
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
    property var warnings: []
    property var rateLimit: null
    property string _stdout: ""
    property string _stderr: ""
    property bool refreshQueued: false
    property string markingNotificationId: ""
    property bool markingAllNotifications: false
    property string notificationActionStatus: ""
    property string _markStdout: ""
    property string _markStderr: ""
    // Thread IDs waiting for PATCH after GitHub confirmed them locally. An
    // in-flight refresh must not restore these rows, or the bar stays lit until
    // the next poll even though the user already opened or marked the thread.
    property var hiddenNotifications: ({})
    property var markQueue: []
    // Single-thread and bulk marking share one process, so the panel gates every
    // entry point on this rather than on whichever flag a given call happens to
    // set. A caller added later inherits the guard instead of having to know.
    readonly property bool marking: markProcess.running
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

    function helperPath() {
        return decodeURIComponent(Qt.resolvedUrl("omarchy-github-fetch").toString().replace(/^file:\/\//, ""));
    }

    function command() {
        return [helperPath(), "--include-archived", boolSetting("includeArchived", false) ? "true" : "false", "--include-forks", boolSetting("includeForks", false) ? "true" : "false", "--repository-scope", repositoryMode(), "--include-archived-reviews", boolSetting("includeArchivedReviewRequests", false) ? "true" : "false", "--include-draft-reviews", boolSetting("includeDraftReviewRequests", false) ? "true" : "false", "--action-scan", actionMode(), "--action-repo-limit", String(intSetting("actionScanRepoLimit", 15, 5, 200)), "--concurrency", String(intSetting("actionScanConcurrency", 6, 1, 12)), "--failed-days", String(intSetting("failedActionDays", 7, 1, 30)), "--failed-limit", String(intSetting("failedActionLimit", 20, 1, 100))];
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
        if (fetchProcess.running || markProcess.running || markQueue.length === 0)
            return false;

        var value = String(markQueue[0] || "");
        markQueue = markQueue.slice(1);
        if (value === "")
            return startQueuedMark();

        actionStatusTimer.stop();
        markingNotificationId = value;
        notificationActionStatus = "Marking notification read…";
        _markStdout = "";
        _markStderr = "";
        markProcess.command = [helperPath(), "--mark-notification-read", value];
        markProcess.running = true;
        return true;
    }

    function refresh() {
        if (fetchProcess.running || markProcess.running || markQueue.length > 0) {
            refreshQueued = true;
            return ;
        }
        refreshQueued = false;
        loading = true;
        _stdout = "";
        _stderr = "";
        fetchProcess.command = command();
        fetchProcess.running = true;
    }

    function apply(raw) {
        try {
            var data = JSON.parse(String(raw || ""));
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
        if (value === "")
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
        if (notifications.length === 0 || loading || fetchProcess.running || markProcess.running)
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
        if (confirmed === "" || loading || fetchProcess.running || markProcess.running)
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
        notificationActionStatus = "Marking all notifications read…";
        _markStdout = "";
        _markStderr = "";
        var commandLine = [helperPath(), "--mark-all-read-before", String(snapshot.boundary || "")];
        for (var i = 0; i < snapshot.boundaryIds.length; i++)
            commandLine.push("--mark-boundary-notification", String(snapshot.boundaryIds[i]));
        markProcess.command = commandLine;
        markProcess.running = true;
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

    Process {
        id: fetchProcess

        running: false
        command: []
        onExited: function(exitCode) {
            root.loading = false;
            var stdout = String(output.text || root._stdout || "");
            var stderr = String(errors.text || root._stderr || "").trim();
            if (stdout.trim() !== "") {
                root.apply(stdout);
            } else {
                root.state = "error";
                root.message = stderr !== "" ? stderr : "GitHub data refresh failed.";
            }
            if (root.startQueuedMark())
                return ;

            if (root.refreshQueued) {
                root.refreshQueued = false;
                Qt.callLater(root.refresh);
            }
        }

        stdout: StdioCollector {
            id: output

            waitForEnd: true
            onStreamFinished: root._stdout = text
        }

        stderr: StdioCollector {
            id: errors

            waitForEnd: true
            onStreamFinished: root._stderr = text
        }

    }

    Process {
        id: markProcess

        running: false
        command: []
        onExited: function(exitCode) {
            var response = null;
            try {
                response = JSON.parse(String(markOutput.text || root._markStdout || ""));
            } catch (error) {
            }
            var all = root.markingAllNotifications;
            var markedId = root.markingNotificationId;
            if (exitCode === 0 && response && response.state === "ready") {
                root.notificationActionStatus = all ? "Notifications marked read. Refreshing…" : "Notification marked read. Refreshing…";
            } else {
                var fallback = all ? "Could not mark all notifications read." : "Could not mark notification read.";
                root.notificationActionStatus = response && response.message ? String(response.message) : String(markErrors.text || root._markStderr || fallback).trim();
                if (!all && markedId !== "")
                    root.restoreHiddenNotification(markedId);
            }
            root.markingNotificationId = "";
            root.markingAllNotifications = false;
            actionStatusTimer.restart();
            if (root.startQueuedMark())
                return ;

            // GitHub is authoritative after every attempt. This reconciles
            // successful, failed, and partially completed bulk operations.
            root.refreshQueued = false;
            Qt.callLater(root.refresh);
        }

        stdout: StdioCollector {
            id: markOutput

            waitForEnd: true
            onStreamFinished: root._markStdout = text
        }

        stderr: StdioCollector {
            id: markErrors

            waitForEnd: true
            onStreamFinished: root._markStderr = text
        }

    }

}
