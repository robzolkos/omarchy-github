#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PANEL_SOURCE=$(<"$ROOT/Panel.qml")

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() {
  [[ $PANEL_SOURCE == *"$1"* ]] || fail "$2"
}
assert_not_contains() {
  [[ $PANEL_SOURCE != *"$1"* ]] || fail "$2"
}

assert_contains 'moduleName: "pranavbabu.gitlab"' \
  "the widget id is not namespaced for the GitLab plugin"
assert_contains 'ipcTarget: "pranavbabu.gitlab"' \
  "the IPC target does not match the widget id"
assert_contains 'Service { id: gitlab; settings: root.settings }' \
  "the dashboard service is not wired to the current settings"

assert_contains 'glyph: broken ? "󰅖" : (running ? "󰑮" : (checks === "SUCCESS" ? "󰄬" : ""))' \
  "authored merge requests without checks do not use the merge request glyph"
assert_contains $'text: linkRow.title\n          textFormat: Text.PlainText' \
  "row titles are not forced to plain text"
assert_contains $'text: linkRow.detail\n          textFormat: Text.PlainText' \
  "row details are not forced to plain text"
assert_contains $'text: gitlab.notificationActionStatus\n            textFormat: Text.PlainText' \
  "notification action status is not forced to plain text"
assert_contains $'return summary\n              }\n              textFormat: Text.PlainText' \
  "dashboard warning text is not forced to plain text"

# The bulk mark-all wiring stays prepare/confirm shaped like the GitHub
# original, even though GitLab has no timestamp boundary to protect: the
# panel still only ever submits a snapshot the service already re-validated.
assert_contains $'actionText: "Mark all read"\n            actionBusyText: "Marking…"\n            actionEnabled: gitlab.state === "ready" && !gitlab.loading\n            actionBusy: gitlab.marking\n            actionRevision: gitlab.notificationsRevision\n            actionPrepare: function() { return gitlab.prepareMarkAllNotificationsRead() }\n            onActionTriggered: function(prepared) { gitlab.markAllNotificationsRead(prepared) }' \
  "notification bulk action is not bound to the prepared displayed snapshot"
assert_contains $'onActionBusyChanged: if (section.actionBusy) section.disarmAction()\n    onActionEnabledChanged: if (!section.actionEnabled) section.disarmAction()\n    onActionRevisionChanged: if (section.actionArmed) section.disarmAction()' \
  "bulk confirmation is not invalidated when notification state changes"
assert_contains $'var confirmed = section.preparedAction\n          section.disarmAction()\n          section.actionTriggered(confirmed)' \
  "bulk action does not submit the originally prepared snapshot"
assert_contains $'function activateCursor() {\n    if (!selectedTarget) return\n    openRow(selectedTarget.kind, selectedTarget.row.id, selectedTarget.row.url)' \
  "opening a notification from the keyboard does not mark it read"
assert_contains $'function openRow(kind, id, url) {\n    var target = String(url || "")\n    var notificationId = String(id || "")\n    openUrl(target)\n    if (kind === "notification") gitlab.markNotificationRead(notificationId)' \
  "opening a notification marks it before launching the URL"
assert_contains $'function markSelectedRead() {\n    if (selectedTarget && selectedTarget.kind === "notification") gitlab.markNotificationRead(String(selectedTarget.row.id || ""))' \
  "keyboard notification marking is blocked during refresh"
assert_contains $'onClicked: root.openRow(linkRow.rowKind, linkRow.notificationId || linkRow.rowId, linkRow.url)' \
  "clicking a notification does not open and mark it read"
assert_contains $'if (gitlab.linkBehavior === "Browser tab") Quickshell.execDetached(["omarchy-launch-browser", value])\n    else Quickshell.execDetached(["omarchy-launch-webapp", value])' \
  "the open-links setting does not choose between the browser and the web app window"

# updateEntryInline rewrites the shell.json entry whole, so a persist that does
# not carry the current settings forward silently drops every other setting.
assert_contains $'var entry = { id: root.moduleName }\n    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]' \
  "persisting a setting does not merge the entry from the current settings"
assert_contains 'root.bar.shell.updateEntryInline(root.moduleName, entry)' \
  "settings changes are not written back to shell.json"
# Dropdown writes `value` imperatively on selection, which destroys a plain
# inline binding the first time a row is picked.
assert_contains $'Binding on value { value: gitlab.linkBehavior }' \
  "the open-links dropdown does not re-assert the persisted value"
assert_contains $'Binding on value { value: String(root.setting("projectScope", "Owned")) }' \
  "the project scope dropdown does not re-assert the persisted value"
assert_contains 'blocked: root.settingsOpen || search.activeFocus' \
  "the key catcher steals keys from the settings controls"
assert_contains 'visible: !root.settingsOpen' \
  "the dashboard stays visible behind the settings page"
assert_contains 'visible: root.settingsOpen' \
  "the settings page is always visible"
assert_contains $'pageFlip.stop()\n      settingsOpen = false' \
  "closing the panel leaves it on the settings page"
assert_contains $'id: readActionStrip\n      visible: linkRow.showReadAction\n      anchors.right: parent.right\n      anchors.top: parent.top\n      anchors.bottom: parent.bottom\n      width: Style.space(32)' \
  "notification read target does not fill the row height at its right edge"
assert_contains $'function notificationRows() {\n    var page = Math.max(0, Math.min(notificationsPage, notificationPageCount() - 1))' \
  "notifications are not paged in five-item windows"
assert_contains $'onPreviousPage: root.notificationsPage = Math.max(0, root.notificationsPage - 1)\n            onNextPage: root.notificationsPage = Math.min(root.notificationPageCount() - 1, root.notificationsPage + 1)' \
  "notification page controls do not clamp their range"
assert_contains $'showReadAction: true\n      showTrailingIndicator: false\n      notificationId: String(modelData.id || "")' \
  "notification rows retain an open-link indicator beside their read action"
assert_contains $'title: "ASSIGNED ISSUES"\n            count: gitlab.assignedIssues.length\n            model: root.sectionRows(gitlab.assignedIssues, root.issuesExpanded)\n            expanded: root.issuesExpanded\n            footerButtonsBordered: true\n            openUrl: gitlab.host + "/dashboard/issues?assignee_username=" + gitlab.login' \
  "assigned-issues open control does not retain its matching border"
assert_contains 'readonly property bool showAction: section.count > 0 && section.actionText !== ""' \
  "bulk notification action disappears while data is loading"
assert_contains 'enabled: section.actionEnabled && !section.actionBusy' \
  "bulk notification action is not disabled until it is ready"

assert_contains $'function applyPanelWheel(event) {\n    if (!panelFlick || (sortPicker && sortPicker.popupOpen)) return false' \
  "the panel still uses Flickable's default wheel distance"
assert_contains $'panelFlick.contentY = Math.max(0, Math.min(maxY, panelFlick.contentY - wheel.steps * Style.space(80)))' \
  "a mouse-wheel notch does not move about one row"
assert_contains $'ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }\n        // Must be a direct child of Flickable or Qt keeps the default\n        // 1–2px wheel distance and this handler never runs.\n        WheelHandler {\n          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad' \
  "the wheel handler is not a direct child of the panel Flickable"

# GitLab-specific fidelity: terminology, icon, and dashboard deep links.
assert_contains 'text: ""' \
  "the bar icon is not the GitLab glyph"
assert_contains 'title: gitlab.login !== "" ? "GitLab · " + gitlab.login : "GitLab"' \
  "the hero title does not read as a GitLab dashboard"
assert_contains 'gitlab.pipelineCount + " active pipelines"' \
  "the hero summary does not describe pipelines rather than actions"
assert_contains 'title: "MY MERGE REQUESTS"' \
  "the authored section is not renamed to GitLab's merge request terminology"
assert_contains 'title: "RUNNING PIPELINES"' \
  "the active-runs section is not renamed to pipelines"
assert_contains 'title: "RECENT FAILED PIPELINES"' \
  "the failed-runs section is not renamed to pipelines"
assert_contains 'openUrl: gitlab.host + "/dashboard/todos"' \
  "the notifications section does not deep-link to the GitLab todos dashboard"
assert_contains 'openUrl: gitlab.host + "/dashboard/merge_requests?reviewer_username=" + gitlab.login' \
  "the review requests section does not deep-link with the resolved username"
assert_contains 'text: "Open in GitLab  󰅂"' \
  "the section footer still says Open in GitHub"
assert_contains 'gitlab.fetchedProjectScope === "owned" ? "OWNED PROJECTS  " : "PROJECTS  "' \
  "the project heading does not follow the fetched scope"
assert_contains '"No projects loaded."' \
  "the project empty state still claims a scope"
assert_contains 'detail: modelData.repository + " !" + modelData.number' \
  "the merge request row does not use GitLab's ! reference prefix"
assert_contains 'glyph: modelData.type === "MergeRequest" ? "" : "󰍩"' \
  "the notification glyph does not recognise GitLab's MergeRequest target type"

echo "panel source tests passed"
