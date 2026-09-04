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

assert_contains 'String(setting("provider", "GitHub")).toLowerCase() === "gitlab" ? "gitlab" : "github"' \
  "an unrecognised provider does not fall back to GitHub"
assert_contains 'var name = root.provider === "gitlab" ? "omarchy-gitlab-fetch" : "omarchy-github-fetch";' \
  "helperPath does not pick the helper script by provider"
assert_contains $'String(setting("repositoryScope", "Owned")).toLowerCase() === "wider" ? "wider" : "owned";' \
  "an unrecognised repository scope no longer falls back to the narrower one"
assert_contains '"--repository-scope", repositoryScopeMode()' \
  "the repository scope setting is not passed to the helper"
assert_contains 'fetchedRepositoryScope = String(data.repositoryScope || "owned");' \
  "the panel cannot tell which scope the payload was fetched with"
assert_contains $'if (value === "all")\n            return "all";' \
  "the full scan does not require an exact setting match"
assert_contains $'if (root.provider === "gitlab") {\n            var hostSetting = String(setting("gitlabHost", "")).trim();\n            if (hostSetting !== "")\n                args.push("--hostname", hostSetting);\n        }' \
  "a configured self-hosted GitLab host is not forwarded to the helper, or leaks into a GitHub command line"

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

# The two providers genuinely disagree on bulk marking (GitHub has a
# timestamp boundary endpoint; GitLab has only individual todo marks), so
# both implementations must survive in one function selected by provider.
assert_contains 'function canonicalNotificationTimestamp(value) {' \
  "the GitHub timestamp-boundary machinery was dropped"
assert_contains 'if (root.provider === "gitlab") {' \
  "prepareMarkAllNotificationsRead does not branch on provider"
assert_contains 'return JSON.stringify({ids: ids, revision: notificationsRevision});' \
  "the GitLab bulk-mark snapshot does not capture its displayed ids and revision"
assert_contains 'return JSON.stringify({boundary: boundary, boundaryIds: boundaryIds, revision: notificationsRevision});' \
  "the GitHub bulk-mark snapshot does not capture its boundary ids and revision"
assert_contains $'function prepareMarkAllNotificationsRead() {\n        if (notifications.length === 0 || loading || fetchProcess.running || markProcess.running)\n            return "";' \
  "bulk confirmation can be prepared during refresh or marking"
assert_contains $'function markAllNotificationsRead(prepared) {\n        var confirmed = String(prepared || "");\n        if (confirmed === "" || loading || fetchProcess.running || markProcess.running)\n            return ;' \
  "bulk marking is not blocked during refresh"
assert_contains $'if (confirmed !== prepareMarkAllNotificationsRead()) {\n            notificationActionStatus = "Notifications changed. Confirm again.";' \
  "bulk marking does not verify the confirmed snapshot"
assert_contains $'commandLine = [helperPath()];\n            for (var i = 0; i < snapshot.ids.length; i++)\n                commandLine.push("--mark-notification-read", String(snapshot.ids[i]));' \
  "GitLab bulk marking does not mark every displayed id individually"
assert_contains $'commandLine = [helperPath(), "--mark-all-read-before", String(snapshot.boundary || "")];\n            for (var j = 0; j < snapshot.boundaryIds.length; j++)\n                commandLine.push("--mark-boundary-notification", String(snapshot.boundaryIds[j]));' \
  "GitHub bulk marking does not protect same-second arrivals with a boundary"
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
assert_contains $'// The forge is authoritative after every attempt. This reconciles\n            // successful, failed, and partially completed bulk operations.\n            root.refreshQueued = false;\n            Qt.callLater(root.refresh);' \
  "notification marking does not reconcile every result with an authoritative refresh"
assert_not_contains 'root.notifications = root.notifications.filter' \
  "notification marking still hides rows using stale local data"

# Check/pipeline status vocabulary: omarchy-gitlab-fetch already folds
# GitLab's own pipeline status enum down into this GitHub-shaped set before
# it ever reaches the service, so this logic is shared unchanged.
assert_contains 'value === "FAILURE" || value === "ERROR"' \
  "broken check/pipeline detection does not match the helpers' shared folded vocabulary"
assert_contains 'value === "PENDING" || value === "EXPECTED"' \
  "running check/pipeline detection does not match the helpers' shared folded vocabulary"
assert_contains 'readonly property int runCount: runs.length' \
  "the alarming run count is not derived from the runs list"
assert_contains 'readonly property int failingAuthoredCount: authored.filter(function(item) {' \
  "failing authored items are not counted toward the alarming state"

# Switching Provider must actually re-fetch, and a late response from the
# previous provider must never land under the new provider's terminology.
assert_contains 'onProviderChanged: {' \
  "switching the provider setting does not trigger any handler"
assert_contains $'onProviderChanged: {\n        notifications = [];\n        hiddenNotifications = {};\n        markQueue = [];' \
  "switching providers does not clear the previous provider's notifications and mark queue"
assert_contains $'        state = "loading";\n        message = "Loading…";\n        refresh();\n    }' \
  "switching providers does not trigger an immediate refresh"
assert_contains $'var payloadProvider = String(data.provider || "");\n            if (payloadProvider !== "" && payloadProvider !== root.provider)\n                return ;' \
  "apply() does not discard a response from a stale provider"

echo "service source tests passed"
