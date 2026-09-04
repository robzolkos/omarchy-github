#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SERVICE_SOURCE=$(<"$ROOT/Service.qml")

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() {
  [[ $SERVICE_SOURCE == *"$1"* ]] || fail "$2"
}
assert_not_contains() {
  [[ $SERVICE_SOURCE != *"$1"* ]] || fail "$2"
}

assert_contains 'String(setting("projectScope", "Owned")).toLowerCase() === "member of" ? "membership" : "owned"' \
  "an unrecognised project scope no longer falls back to the narrower one"
assert_contains '"--project-scope", projectScopeMode()' \
  "the project scope setting is not passed to the helper"
assert_contains 'fetchedProjectScope = String(data.projectScope || "owned");' \
  "the panel cannot tell which scope the payload was fetched with"
assert_contains $'if (value === "all projects")\n            return "all";' \
  "the full pipeline scan does not require an exact setting match"
assert_contains $'var hostSetting = String(setting("gitlabHost", "")).trim();\n        if (hostSetting !== "")\n            args.push("--hostname", hostSetting);' \
  "a configured self-hosted host is not forwarded to the helper"

assert_contains $'function refresh() {\n        if (fetchProcess.running || markProcess.running || markQueue.length > 0) {\n            refreshQueued = true;\n            return ;\n        }' \
  "refresh and notification marking are not serialized"
assert_contains $'notifications = visibleNotifications(data.notifications);\n            notificationsRevision++;' \
  "notification refreshes do not invalidate prepared confirmations"
assert_contains $'hideNotification(value);\n        enqueueMark(value);\n        startQueuedMark();' \
  "single-notification marking is dropped during refresh"
assert_contains 'notifications = [item].concat(notifications);' \
  "failed notification marking does not restore the hidden row"
assert_contains 'String(setting("linkBehavior", "Web app window")).toLowerCase() === "browser tab" ? "Browser tab" : "Web app window"' \
  "an unrecognised open-links value does not fall back to the web app window"

# GitLab has no "mark everything before a timestamp" endpoint, so bulk marking
# is a snapshot of displayed ids re-validated against the current list, not a
# boundary computed from notification timestamps.
assert_not_contains 'canonicalNotificationTimestamp' \
  "bulk marking still carries the GitHub timestamp-boundary machinery"
assert_not_contains 'mark-all-read-before' \
  "bulk marking still asks the helper for a timestamp boundary"
assert_contains $'function prepareMarkAllNotificationsRead() {\n        if (notifications.length === 0 || loading || fetchProcess.running || markProcess.running)\n            return "";' \
  "bulk confirmation can be prepared during refresh or marking"
assert_contains $'if (!/^\\d+$/.test(id)) {\n                notificationActionStatus = "Refresh before marking everything read.";' \
  "bulk confirmation accepts invalid notification ids"
assert_contains 'return JSON.stringify({ids: ids, revision: notificationsRevision});' \
  "bulk confirmation does not capture its displayed ids and revision"
assert_contains $'function markAllNotificationsRead(prepared) {\n        var confirmed = String(prepared || "");\n        if (confirmed === "" || loading || fetchProcess.running || markProcess.running)\n            return ;' \
  "bulk marking is not blocked during refresh"
assert_contains $'if (confirmed !== prepareMarkAllNotificationsRead()) {\n            notificationActionStatus = "Notifications changed. Confirm again.";' \
  "bulk marking does not verify the confirmed snapshot"
assert_contains $'var commandLine = [helperPath()];\n        for (var i = 0; i < snapshot.ids.length; i++)\n            commandLine.push("--mark-notification-read", String(snapshot.ids[i]));' \
  "bulk marking does not mark every displayed id individually"
assert_contains $'function hideAllNotifications() {\n        var ids = [];\n        var hidden = copyMap(hiddenNotifications);\n        var remaining = [];\n        for (var i = 0; i < notifications.length; i++) {' \
  "bulk marking does not batch its optimistic removal"
assert_contains $'hiddenNotifications = hidden;\n            notifications = remaining;\n            notificationsRevision++;' \
  "bulk marking repeatedly updates the notification model"
assert_contains $'function restoreHiddenNotifications(ids) {\n        var values = Array.isArray(ids) ? ids : [];\n        for (var i = values.length - 1; i >= 0; i--)' \
  "failed bulk marking does not preserve notification order"
assert_contains $'markingAllNotifications = true;\n        markingAllNotificationIds = hideAllNotifications();\n        notificationActionStatus = "Marking all notifications read…";' \
  "bulk marking does not provide immediate visible feedback"
assert_contains $'if (all)\n                    root.restoreHiddenNotifications(root.markingAllNotificationIds);\n                else if (markedId !== "")' \
  "failed bulk marking does not restore its displayed notifications"
assert_contains $'// GitLab is authoritative after every attempt. This reconciles\n            // successful, failed, and partially completed bulk operations.\n            root.refreshQueued = false;\n            Qt.callLater(root.refresh);' \
  "notification marking does not reconcile every result with an authoritative refresh"
assert_not_contains 'root.notifications = root.notifications.filter' \
  "notification marking still hides rows using stale local data"

# Pipeline status vocabulary: the helper folds GitLab's own pipeline status
# enum down into this GitHub-shaped set before it ever reaches the service.
assert_contains 'value === "FAILURE" || value === "ERROR"' \
  "broken pipeline detection does not match the helper's folded vocabulary"
assert_contains 'value === "PENDING" || value === "EXPECTED"' \
  "running pipeline detection does not match the helper's folded vocabulary"
assert_contains 'readonly property int pipelineCount: pipelines.length' \
  "the alarming pipeline count is not derived from the pipelines list"
assert_contains 'readonly property int failingMergeRequestCount: myMergeRequests.filter(function(item) {' \
  "failing merge requests are not counted toward the alarming state"

echo "service source tests passed"
