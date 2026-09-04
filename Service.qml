import QtQuick
import Quickshell
import Quickshell.Io

// Forge dashboard data service: one Service for either GitHub or a GitLab
// instance, selected by the `provider` setting. Each helper (omarchy-github-fetch,
// omarchy-gitlab-fetch) emits the same top-level JSON shape (see
// tests/schema-test.sh), so everything below except helperPath(), command(),
// and the two mark-all-read implementations is provider-agnostic.
Item {
    id: root

    property var settings: ({
    })
    property bool loading: false
    property string state: "loading"
    property string message: "Loading…"
    property string host: ""
    property string login: ""
    property string fetchedRepositoryScope: "owned"
    property string fetchedAt: ""
    property var notifications: []
    property int notificationsRevision: 0
    property var reviewRequests: []
    property var assignedIssues: []
    property var authored: []
    property int authoredTotal: 0
    property var runs: []
    property var failedRuns: []
    property var repositories: []
    property var warnings: []
    property var rateLimit: null
    property string _stdout: ""
    property string _stderr: ""
    property bool refreshQueued: false
    property string markingNotificationId: ""
    property bool markingAllNotifications: false
    property var markingAllNotificationIds: []
    property string notificationActionStatus: ""
    property string _markStdout: ""
    property string _markStderr: ""
    // Thread/todo IDs waiting for the mark-as-read round trip after the forge
    // confirmed them locally. An in-flight refresh must not restore these
    // rows, or the bar stays lit until the next poll even though the user
    // already opened or marked the notification.
    property var hiddenNotifications: ({})
    property var markQueue: []
    // Single-notification and bulk marking share one process, so the panel
    // gates every entry point on this rather than on whichever flag a given
    // call happens to set. A caller added later inherits the guard instead of
    // having to know.
    readonly property bool marking: markProcess.running
    readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 900, 60, 3600)
    readonly property int unreadCount: notifications.length
    readonly property int runCount: runs.length
    // A broken check/pipeline on your own pull or merge request is the kind of
    // thing the bar icon exists to surface, so it counts toward the alarming
    // state. Drafts are excluded: a red check on work you have not offered up
    // yet is expected, and it would leave the icon permanently lit.
    readonly property int failingAuthoredCount: authored.filter(function(item) {
        return !item.draft && root.isBrokenCheck(item.checks);
    }).length
    readonly property bool iconAlwaysUnlit: boolSetting("iconAlwaysUnlit", false)
    // An unrecognised value falls back to the web app window rather than the
    // browser, so a stale entry cannot silently revert the default behaviour.
    readonly property string linkBehavior: String(setting("linkBehavior", "Web app window")).toLowerCase() === "browser tab" ? "Browser tab" : "Web app window"
    readonly property bool alarming: !iconAlwaysUnlit && (unreadCount > 0 || runCount > 0 || reviewRequests.length > 0 || failingAuthoredCount > 0)
    // An unrecognised value falls back to GitHub rather than silently pointing
    // at whichever provider happened to run last.
    readonly property string provider: String(setting("provider", "GitHub")).toLowerCase() === "gitlab" ? "gitlab" : "github"

    // Check/pipeline status groupings live here so the alarming count, the row
    // label, and the row glyph cannot drift apart when a state is
    // reclassified. omarchy-gitlab-fetch already folds GitLab's own pipeline
    // status enum down into this GitHub-shaped vocabulary before it ever
    // reaches the service, so this logic is shared unchanged.
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
    // added later falls back to the narrower scope instead of silently
    // widening it. `fetchedRepositoryScope` reports what the last payload was
    // actually fetched with.
    function repositoryScopeMode() {
        return String(setting("repositoryScope", "Owned")).toLowerCase() === "wider" ? "wider" : "owned";
    }

    function scanMode() {
        var value = String(setting("scanBehavior", "Recent")).toLowerCase();
        if (value === "off")
            return "off";

        if (value === "all")
            return "all";

        return "recent";
    }

    function helperPath() {
        var name = root.provider === "gitlab" ? "omarchy-gitlab-fetch" : "omarchy-github-fetch";
        return decodeURIComponent(Qt.resolvedUrl(name).toString().replace(/^file:\/\//, ""));
    }

    function command() {
        var args = [helperPath(), "--include-archived", boolSetting("includeArchived", false) ? "true" : "false", "--include-forks", boolSetting("includeForks", false) ? "true" : "false", "--repository-scope", repositoryScopeMode(), "--include-archived-reviews", boolSetting("includeArchivedReviewRequests", false) ? "true" : "false", "--include-draft-reviews", boolSetting("includeDraftReviewRequests", false) ? "true" : "false", "--scan", scanMode(), "--scan-limit", String(intSetting("scanLimit", 15, 5, 200)), "--concurrency", String(intSetting("scanConcurrency", 6, 1, 12)), "--failed-days", String(intSetting("failedDays", 7, 1, 30)), "--failed-limit", String(intSetting("failedLimit", 20, 1, 100))];
        if (root.provider === "gitlab") {
            var hostSetting = String(setting("gitlabHost", "")).trim();
            if (hostSetting !== "")
                args.push("--hostname", hostSetting);
        }
        return args;
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

    // Switching providers must not leave the previous provider's rows on
    // screen under the new provider's terminology, and must not let a queued
    // mark or a hidden-notification snapshot from the old provider reach the
    // new provider's helper (a GitHub thread id sent to `glab`, for example).
    // refresh() below only queues if a fetch/mark is already in flight; the
    // apply() guard above discards that in-flight response if it lands after
    // this handler has already moved the service on.
    onProviderChanged: {
        notifications = [];
        hiddenNotifications = {};
        markQueue = [];
        markingAllNotificationIds = [];
        notificationsRevision++;
        reviewRequests = [];
        assignedIssues = [];
        authored = [];
        authoredTotal = 0;
        runs = [];
        failedRuns = [];
        repositories = [];
        warnings = [];
        rateLimit = null;
        host = "";
        login = "";
        state = "loading";
        message = "Loading…";
        refresh();
    }

    // A fetch started under the previous provider can still be in flight when
    // the setting flips (onProviderChanged only queues a new refresh; it does
    // not, and cannot, kill the running process). Its response must never
    // land: showing GitHub rows under GitLab terminology, or vice versa, is
    // exactly the bug this whole feature must not have. The already-queued
    // refresh (see onProviderChanged) supersedes it once this process exits.
    function apply(raw) {
        try {
            var data = JSON.parse(String(raw || ""));
            var payloadProvider = String(data.provider || "");
            if (payloadProvider !== "" && payloadProvider !== root.provider)
                return ;

            state = String(data.state || "error");
            message = String(data.message || "");
            host = String(data.host || "");
            login = String(data.login || "");
            fetchedRepositoryScope = String(data.repositoryScope || "owned");
            fetchedAt = String(data.fetchedAt || "");
            notifications = visibleNotifications(data.notifications);
            notificationsRevision++;
            reviewRequests = Array.isArray(data.reviewRequests) ? data.reviewRequests : [];
            assignedIssues = Array.isArray(data.assignedIssues) ? data.assignedIssues : [];
            authored = Array.isArray(data.authored) ? data.authored : [];
            authoredTotal = Number(data.authoredTotal) || authored.length;
            runs = Array.isArray(data.runs) ? data.runs : [];
            failedRuns = Array.isArray(data.failedRuns) ? data.failedRuns : [];
            repositories = Array.isArray(data.repositories) ? data.repositories : [];
            warnings = Array.isArray(data.warnings) ? data.warnings : [];
            rateLimit = data.rateLimit || null;
        } catch (error) {
            state = "error";
            message = "The refresh returned an unreadable response.";
            warnings = [String(error)];
        }
    }

    function markNotificationRead(id) {
        var value = String(id || "");
        if (value === "")
            return ;

        // Drop the row before the round trip. Opening a notification while a
        // refresh is already running used to no-op, so the icon stayed
        // alarming until the next poll even after the user had seen it.
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

    // Capture the exact displayed snapshot on the first click. The panel binds
    // confirmation to notificationsRevision, so any refresh invalidates this
    // prepared value before the destructive second click can run.
    //
    // GitHub can mark everything before a timestamp boundary in one request,
    // preserving same-second arrivals by re-marking only the fetched boundary
    // IDs individually. GitLab's to-do API has no such boundary endpoint, so
    // its snapshot is simply every displayed ID, marked individually; a
    // notification that arrives mid-confirmation is never in that set and
    // stays unread, which is strictly safer than GitHub's same-second edge
    // case. This is the one place the two providers genuinely disagree, so it
    // stays as two explicit implementations rather than a shared one.
    function prepareMarkAllNotificationsRead() {
        if (notifications.length === 0 || loading || fetchProcess.running || markProcess.running)
            return "";

        if (root.provider === "gitlab") {
            var ids = [];
            for (var i = 0; i < notifications.length; i++) {
                var id = String(notifications[i].id || "");
                if (!/^\d+$/.test(id)) {
                    notificationActionStatus = "Refresh before marking everything read.";
                    actionStatusTimer.restart();
                    return "";
                }
                ids.push(id);
            }
            return JSON.stringify({ids: ids, revision: notificationsRevision});
        }

        var boundary = "";
        for (var j = 0; j < notifications.length; j++) {
            var updated = canonicalNotificationTimestamp(notifications[j].updatedAt);
            if (updated === "") {
                notificationActionStatus = "Refresh before marking everything read.";
                actionStatusTimer.restart();
                return "";
            }
            if (updated > boundary)
                boundary = updated;
        }

        var boundaryIds = [];
        for (var k = 0; k < notifications.length; k++) {
            if (String(notifications[k].updatedAt || "") !== boundary)
                continue;
            var boundaryId = String(notifications[k].id || "");
            if (!/^\d+$/.test(boundaryId)) {
                notificationActionStatus = "Refresh before marking everything read.";
                actionStatusTimer.restart();
                return "";
            }
            boundaryIds.push(boundaryId);
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
        markingAllNotificationIds = hideAllNotifications();
        notificationActionStatus = "Marking all notifications read…";
        _markStdout = "";
        _markStderr = "";
        var commandLine;
        if (root.provider === "gitlab") {
            commandLine = [helperPath()];
            for (var i = 0; i < snapshot.ids.length; i++)
                commandLine.push("--mark-notification-read", String(snapshot.ids[i]));
        } else {
            commandLine = [helperPath(), "--mark-all-read-before", String(snapshot.boundary || "")];
            for (var j = 0; j < snapshot.boundaryIds.length; j++)
                commandLine.push("--mark-boundary-notification", String(snapshot.boundaryIds[j]));
        }
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
                root.message = stderr !== "" ? stderr : "Data refresh failed.";
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

            // The forge is authoritative after every attempt. This reconciles
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
