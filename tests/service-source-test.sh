#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SERVICE_SOURCE=$(<"$ROOT/Service.qml")

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() {
  [[ $SERVICE_SOURCE == *"$1"* ]] || fail "$2"
}
assert_contains 'String(setting("repositoryScope", "Owned")).toLowerCase() === "owned and organizations" ? "organizations" : "owned"' \
  "an unrecognised repository scope no longer falls back to the narrower one"
assert_contains '"--repository-scope", repositoryMode()' \
  "the repository scope setting is not passed to the helper"
assert_contains 'fetchedRepositoryScope = String(data.repositoryScope || "owned");' \
  "the panel cannot tell which scope the payload was fetched with"
assert_contains $'if (value === "all repositories")\n            return "all";' \
  "the full Actions scan does not require an exact setting match"

assert_not_contains() {
  [[ $SERVICE_SOURCE != *"$1"* ]] || fail "$2"
}

assert_contains $'function refresh() {\n        if (fetchProcess.running || markProcess.running || markQueue.length > 0) {\n            refreshQueued = true;\n            return ;\n        }' \
  "refresh and notification marking are not serialized"
assert_contains $'notifications = visibleNotifications(data.notifications);\n            notificationsRevision++;' \
  "notification refreshes do not invalidate prepared confirmations"
assert_contains $'hideNotification(value);\n        enqueueMark(value);\n        startQueuedMark();' \
  "single-notification marking is dropped during refresh"
assert_contains 'notifications = [item].concat(notifications);' \
  "failed notification marking does not restore the hidden row"
assert_not_contains $'if (value === "" || loading || fetchProcess.running || markProcess.running)' \
  "single-notification marking is still blocked during refresh"
assert_contains 'String(setting("linkBehavior", "Web app window")).toLowerCase() === "browser tab" ? "Browser tab" : "Web app window"' \
  "an unrecognised open-links value does not fall back to the web app window"

assert_contains $'function canonicalNotificationTimestamp(value) {\n        var text = String(value || "");\n        if (!/^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$/.test(text))\n            return "";' \
  "notification boundaries are not shape validated"
assert_contains 'return milliseconds <= Date.now() ? text : "";' \
  "future notification boundaries are accepted"
assert_contains $'function prepareMarkAllNotificationsRead() {\n        if (notifications.length === 0 || loading || fetchProcess.running || markProcess.running)\n            return "";' \
  "bulk confirmation can be prepared during refresh or marking"
assert_contains $'if (!/^\\d+$/.test(id)) {\n                notificationActionStatus = "Refresh before marking everything read.";' \
  "bulk confirmation accepts invalid boundary notification IDs"
assert_contains 'return JSON.stringify({boundary: boundary, boundaryIds: boundaryIds, revision: notificationsRevision});' \
  "bulk confirmation does not capture its boundary IDs and revision"
assert_contains $'function markAllNotificationsRead(prepared) {\n        var confirmed = String(prepared || "");\n        if (confirmed === "" || loading || fetchProcess.running || markProcess.running)\n            return ;' \
  "bulk marking is not blocked during refresh"
assert_contains $'if (confirmed !== prepareMarkAllNotificationsRead()) {\n            notificationActionStatus = "Notifications changed. Confirm again.";' \
  "bulk marking does not verify the confirmed snapshot"
assert_contains $'var commandLine = [helperPath(), "--mark-all-read-before", String(snapshot.boundary || "")];\n        for (var i = 0; i < snapshot.boundaryIds.length; i++)\n            commandLine.push("--mark-boundary-notification", String(snapshot.boundaryIds[i]));' \
  "bulk marking does not protect same-second arrivals"
assert_contains $'// GitHub is authoritative after every attempt. This reconciles\n            // successful, failed, and partially completed bulk operations.\n            root.refreshQueued = false;\n            Qt.callLater(root.refresh);' \
  "notification marking does not reconcile every result with an authoritative refresh"
assert_not_contains 'root.notifications = root.notifications.filter' \
  "notification marking still hides rows using stale local data"

echo "service source tests passed"
