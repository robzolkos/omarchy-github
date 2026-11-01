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
    // One entry per gh login when gh holds several (login, state, message,
    // rateLimit, contributions, myPullRequestsTotal); empty for a single
    // credential, which keeps the panel exactly as it was.
    property var accounts: []
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
    // Year-long contribution calendar for the top-of-panel heatmap. Bucketed
    // by the helper into 5 levels (0..4) so the panel never re-counts.
    property var contributions: ({total: 0, days: []})
    property bool settingsReady: false
    readonly property bool includeContributions: boolSetting("includeContributions", true)
    onIncludeContributionsChanged: {
        if (settingsReady && includeContributions)
            refresh();
    }
    // Normalised the same way as linkBehavior: matched against the known
    // options rather than substring-matched, so an unknown value falls back
    // to the default position instead of silently snapping elsewhere.
    readonly property string contributionsPosition: {
        var value = String(setting("contributionsPosition", "Top")).toLowerCase()
        if (value === "middle (above repositories)") return "Middle (above repositories)"
        if (value === "bottom") return "Bottom"
        return "Top"
    }
    property string _stdout: ""
    property string _stderr: ""
    property bool refreshQueued: false
    property bool refreshQueuedAutomatic: false
    property string markingNotificationId: ""
    property bool markingAllNotifications: false
    property var markingAllNotificationIds: []
    property string notificationActionStatus: ""
    property string _markStdout: ""
    property string _markStderr: ""
    // Thread IDs waiting for PATCH after GitHub confirmed them locally. An
    // in-flight refresh must not restore these rows, or the bar stays lit until
    // the next poll even though the user already opened or marked the thread.
    property var hiddenNotifications: ({})
    // Successful marks stay hidden until any older in-flight fetch has applied.
    // The next authoritative refresh then releases them so genuinely new
    // activity on the same thread can become visible again.
    property var pendingNotificationReconciliationIds: []
    property var markQueue: []
    // The account of each thread waiting in markQueue. A refresh can drop the
    // row before its turn comes, and the mark must still go out as its owner.
    property var markAccounts: ({})
    // Bulk marks run once per account, because each account has its own
    // newest-second boundary and token. The commands still waiting after the
    // one now running.
    property var markAllCommands: []
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

    function command(automatic) {
        var argv = [helperPath(), "--include-archived", boolSetting("includeArchived", false) ? "true" : "false", "--include-forks", boolSetting("includeForks", false) ? "true" : "false", "--repository-scope", repositoryMode(), "--include-archived-reviews", boolSetting("includeArchivedReviewRequests", false) ? "true" : "false", "--include-draft-reviews", boolSetting("includeDraftReviewRequests", false) ? "true" : "false", "--include-contributions", includeContributions ? "true" : "false", "--action-scan", actionMode(), "--action-repo-limit", String(intSetting("actionScanRepoLimit", 15, 5, 200)), "--concurrency", String(intSetting("actionScanConcurrency", 6, 1, 12)), "--failed-days", String(intSetting("failedActionDays", 7, 1, 30)), "--failed-limit", String(intSetting("failedActionLimit", 20, 1, 100))];
        if (automatic)
            argv = argv.concat(["--automatic", "--refresh-interval", String(refreshIntervalSec)]);
        return argv;
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

    function hideAllNotifications(account) {
        var scope = String(account || "");
        var ids = [];
        var hidden = copyMap(hiddenNotifications);
        var remaining = [];
        for (var i = 0; i < notifications.length; i++) {
            var item = notifications[i];
            var id = String(item.id || "");
            if (id !== "" && (scope === "" || String(item.account || "") === scope)) {
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

    function queueNotificationReconciliation(ids) {
        var values = Array.isArray(ids) ? ids : [];
        var pending = pendingNotificationReconciliationIds.slice();
        for (var i = 0; i < values.length; i++) {
            var id = String(values[i] || "");
            if (id !== "" && pending.indexOf(id) === -1)
                pending.push(id);
        }
        pendingNotificationReconciliationIds = pending;
    }

    function releasePendingNotificationReconciliation() {
        if (pendingNotificationReconciliationIds.length === 0)
            return ;

        var hidden = copyMap(hiddenNotifications);
        for (var i = 0; i < pendingNotificationReconciliationIds.length; i++)
            delete hidden[pendingNotificationReconciliationIds[i]];
        hiddenNotifications = hidden;
        pendingNotificationReconciliationIds = [];
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
        var account = String(markAccounts[value] || "");
        delete markAccounts[value];
        markProcess.command = [helperPath(), "--mark-notification-read", value].concat(account !== "" ? ["--account", account] : []);
        markProcess.running = true;
        return true;
    }

    // The account a notification row belongs to, whether it is still listed or
    // already hidden; empty for a single credential.
    function notificationAccount(id) {
        var value = String(id || "");
        for (var i = 0; i < notifications.length; i++) {
            if (String(notifications[i].id || "") === value)
                return String(notifications[i].account || "");
        }
        var hidden = hiddenNotifications[value];
        return hidden && hidden.account ? String(hidden.account) : "";
    }

    function initialize(initialSettings) {
        if (settingsReady)
            return ;
        settings = initialSettings || {};
        settingsReady = true;
        automaticRefresh();
    }

    function startRefresh(automatic) {
        if (!settingsReady)
            return ;
        if (fetchProcess.running || markProcess.running || markQueue.length > 0) {
            if (!refreshQueued)
                refreshQueuedAutomatic = automatic;
            else if (!automatic)
                refreshQueuedAutomatic = false;
            refreshQueued = true;
            return ;
        }
        refreshQueued = false;
        refreshQueuedAutomatic = false;
        releasePendingNotificationReconciliation();
        loading = true;
        _stdout = "";
        _stderr = "";
        fetchProcess.command = command(automatic);
        fetchProcess.running = true;
    }

    function refresh() {
        startRefresh(false);
    }

    function automaticRefresh() {
        startRefresh(true);
    }

    function apply(raw) {
        try {
            var data = JSON.parse(String(raw || ""));
            var incomingState = String(data.state || "error");
            var preserveReadyDashboard = incomingState === "rate-limited" && data.preserveDashboard === true && fetchedAt !== "";
            state = incomingState;
            message = String(data.message || "");
            if (!preserveReadyDashboard) {
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
                contributions = data.contributions && Array.isArray(data.contributions.days) ? data.contributions : {total: 0, days: []};
                warnings = Array.isArray(data.warnings) ? data.warnings : [];
            }
            accounts = Array.isArray(data.accounts) ? data.accounts : [];
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
        var account = notificationAccount(value);
        if (account !== "")
            markAccounts[value] = account;

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

    // The newest displayed second among one account's notifications and the
    // thread IDs updated at it, or null when a row cannot be bounded safely.
    function notificationBoundary(rows) {
        var boundary = "";
        for (var i = 0; i < rows.length; i++) {
            var updated = canonicalNotificationTimestamp(rows[i].updatedAt);
            if (updated === "") {
                notificationActionStatus = "Refresh before marking everything read.";
                actionStatusTimer.restart();
                return null;
            }
            if (updated > boundary)
                boundary = updated;
        }

        var boundaryIds = [];
        for (var j = 0; j < rows.length; j++) {
            if (String(rows[j].updatedAt || "") !== boundary)
                continue;
            var id = String(rows[j].id || "");
            if (!/^\d+$/.test(id)) {
                notificationActionStatus = "Refresh before marking everything read.";
                actionStatusTimer.restart();
                return null;
            }
            boundaryIds.push(id);
        }
        return {boundary: boundary, boundaryIds: boundaryIds};
    }

    // Capture the exact displayed boundary on the first click. A refresh must
    // finish before confirmation is prepared so unseen activity cannot be
    // marked read from the older displayed snapshot. Every account has its own
    // boundary, since a later one would also cover unseen arrivals on an
    // account whose newest displayed thread is older; `account` limits the
    // snapshot to one of them.
    function prepareMarkAllNotificationsRead(account) {
        var scope = String(account || "");
        var owners = [];
        var rowsByOwner = {};
        for (var i = 0; i < notifications.length; i++) {
            var owner = String(notifications[i].account || "");
            if (scope !== "" && owner !== scope)
                continue;
            if (rowsByOwner[owner] === undefined) {
                rowsByOwner[owner] = [];
                owners.push(owner);
            }
            rowsByOwner[owner].push(notifications[i]);
        }
        if (owners.length === 0 || loading || fetchProcess.running || markProcess.running)
            return "";

        var groups = [];
        for (var j = 0; j < owners.length; j++) {
            var bound = notificationBoundary(rowsByOwner[owners[j]]);
            if (bound === null)
                return "";
            groups.push({account: owners[j], boundary: bound.boundary, boundaryIds: bound.boundaryIds});
        }
        return JSON.stringify({account: scope, groups: groups, revision: notificationsRevision});
    }

    function markAllCommand(group) {
        var commandLine = [helperPath(), "--mark-all-read-before", String(group.boundary || "")];
        for (var i = 0; i < group.boundaryIds.length; i++)
            commandLine.push("--mark-boundary-notification", String(group.boundaryIds[i]));
        if (group.account)
            commandLine.push("--account", String(group.account));
        return commandLine;
    }

    function startNextMarkAll() {
        if (markAllCommands.length === 0)
            return false;

        _markStdout = "";
        _markStderr = "";
        markProcess.command = markAllCommands[0];
        markAllCommands = markAllCommands.slice(1);
        markProcess.running = true;
        return true;
    }

    function markAllNotificationsRead(prepared) {
        var confirmed = String(prepared || "");
        if (confirmed === "" || loading || fetchProcess.running || markProcess.running)
            return ;

        var snapshot;
        try {
            snapshot = JSON.parse(confirmed);
        } catch (error) {
            notificationActionStatus = "Refresh before marking everything read.";
            actionStatusTimer.restart();
            return ;
        }

        // Recompute immediately before starting. This protects non-panel callers
        // as well as the panel's revision-bound confirmation.
        if (confirmed !== prepareMarkAllNotificationsRead(snapshot ? snapshot.account : "")) {
            notificationActionStatus = "Notifications changed. Confirm again.";
            actionStatusTimer.restart();
            return ;
        }

        actionStatusTimer.stop();
        markingAllNotifications = true;
        markingAllNotificationIds = hideAllNotifications(snapshot.account);
        notificationActionStatus = "Marking all notifications read…";
        markAllCommands = snapshot.groups.map(markAllCommand);
        startNextMarkAll();
    }

    visible: false

    Timer {
        interval: root.refreshIntervalSec * 1000
        repeat: true
        running: root.settingsReady
        onTriggered: root.automaticRefresh()
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
                var automatic = root.refreshQueuedAutomatic;
                root.refreshQueued = false;
                root.refreshQueuedAutomatic = false;
                Qt.callLater(function() { root.startRefresh(automatic); });
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
                if (all && root.startNextMarkAll())
                    return ;

                root.queueNotificationReconciliation(all ? root.markingAllNotificationIds : [markedId]);
                root.notificationActionStatus = all ? "Notifications marked read. Refreshing…" : "Notification marked read. Refreshing…";
            } else {
                // Later accounts are not attempted. Every hidden row returns and
                // the refresh below shows what GitHub really marked.
                root.markAllCommands = [];
                var fallback = all ? "Could not mark all notifications read." : "Could not mark notification read.";
                root.notificationActionStatus = response && response.message ? String(response.message) : String(markErrors.text || root._markStderr || fallback).trim();
                if (all)
                    root.restoreHiddenNotifications(root.markingAllNotificationIds);
                else if (markedId !== "")
                    root.restoreHiddenNotification(markedId);
            }
            root.markingNotificationId = "";
            root.markingAllNotifications = false;
            root.markingAllNotificationIds = [];
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
