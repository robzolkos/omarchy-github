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

assert_contains 'moduleName: "robzolkos.github"' \
  "the widget id changed even though GitLab support must not break existing robzolkos.github installs"
assert_contains 'ipcTarget: "robzolkos.github"' \
  "the IPC target does not match the widget id"
assert_contains 'Service { id: svc; settings: root.settings }' \
  "the dashboard service is not wired to the current settings"
assert_contains 'readonly property var term: svc.provider === "gitlab" ? gitlabTerms : githubTerms' \
  "the panel does not select provider terminology from svc.provider"

# Every provider-specific string lives in the term table, not scattered
# through the panel, so switching Provider actually relabels the dashboard.
python3 - "$ROOT/Panel.qml" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
gh = re.search(r'readonly property var githubTerms: \(\{(.*?)\}\)', src, re.S).group(1)
gl = re.search(r'readonly property var gitlabTerms: \(\{(.*?)\}\)', src, re.S).group(1)
def field(block, key):
    m = re.search(re.escape(key) + r':\s*"([^"]*)"', block)
    return m.group(1) if m else None
checks = [
    ("name", "GitHub", "GitLab"),
    ("myItemsTitle", "MY PULL REQUESTS", "MY MERGE REQUESTS"),
    ("runningTitle", "RUNNING ACTIONS", "RUNNING PIPELINES"),
    ("failedTitle", "RECENT FAILED ACTIONS", "RECENT FAILED PIPELINES"),
    ("itemFilterLabel", "PRs", "MRs"),
    ("activeMetricLabel", "Actions", "Pipelines"),
    ("repoNounTitle", "REPOSITORIES", "PROJECTS"),
    ("ownedRepoNounTitle", "OWNED REPOSITORIES", "OWNED PROJECTS"),
    ("refPrefix", " #", " !"),
]
for key, ghwant, glwant in checks:
    ghgot, glgot = field(gh, key), field(gl, key)
    if ghgot != ghwant:
        sys.exit(f"FAIL: githubTerms.{key} is {ghgot!r}, expected {ghwant!r}")
    if glgot != glwant:
        sys.exit(f"FAIL: gitlabTerms.{key} is {glgot!r}, expected {glwant!r}")
print("term table checks passed")
PY

assert_contains $'text: linkRow.title\n          textFormat: Text.PlainText' \
  "row titles are not forced to plain text"
assert_contains $'text: linkRow.detail\n          textFormat: Text.PlainText' \
  "row details are not forced to plain text"
assert_contains $'text: svc.notificationActionStatus\n            textFormat: Text.PlainText' \
  "notification action status is not forced to plain text"
assert_contains $'return summary\n              }\n              textFormat: Text.PlainText' \
  "dashboard warning text is not forced to plain text"

# The bulk mark-all wiring stays prepare/confirm shaped for both providers,
# even though only GitHub has a timestamp boundary to protect: the panel
# always only ever submits a snapshot the service already re-validated.
assert_contains $'actionText: "Mark all read"\n            actionBusyText: "Marking…"\n            actionEnabled: svc.state === "ready" && !svc.loading\n            actionBusy: svc.marking\n            actionRevision: svc.notificationsRevision\n            actionPrepare: function() { return svc.prepareMarkAllNotificationsRead() }\n            onActionTriggered: function(prepared) { svc.markAllNotificationsRead(prepared) }' \
  "notification bulk action is not bound to the prepared displayed snapshot"
assert_contains $'onActionBusyChanged: if (section.actionBusy) section.disarmAction()\n    onActionEnabledChanged: if (!section.actionEnabled) section.disarmAction()\n    onActionRevisionChanged: if (section.actionArmed) section.disarmAction()' \
  "bulk confirmation is not invalidated when notification state changes"
assert_contains $'var confirmed = section.preparedAction\n          section.disarmAction()\n          section.actionTriggered(confirmed)' \
  "bulk action does not submit the originally prepared snapshot"
assert_contains $'function activateCursor() {\n    if (!selectedTarget) return\n    openRow(selectedTarget.kind, selectedTarget.row.id, selectedTarget.row.url)' \
  "opening a notification from the keyboard does not mark it read"
assert_contains $'function openRow(kind, id, url) {\n    var target = String(url || "")\n    var notificationId = String(id || "")\n    openUrl(target)\n    if (kind === "notification") svc.markNotificationRead(notificationId)' \
  "opening a notification marks it before launching the URL"
assert_contains $'function markSelectedRead() {\n    if (selectedTarget && selectedTarget.kind === "notification") svc.markNotificationRead(String(selectedTarget.row.id || ""))' \
  "keyboard notification marking is blocked during refresh"
assert_contains $'onClicked: root.openRow(linkRow.rowKind, linkRow.notificationId || linkRow.rowId, linkRow.url)' \
  "clicking a notification does not open and mark it read"
assert_contains $'if (svc.linkBehavior === "Browser tab") Quickshell.execDetached(["omarchy-launch-browser", value])\n    else Quickshell.execDetached(["omarchy-launch-webapp", value])' \
  "the open-links setting does not choose between the browser and the web app window"

# updateEntryInline rewrites the shell.json entry whole, so a persist that does
# not carry the current settings forward silently drops every other setting.
assert_contains $'var entry = { id: root.moduleName }\n    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]' \
  "persisting a setting does not merge the entry from the current settings"
assert_contains 'root.bar.shell.updateEntryInline(root.moduleName, entry)' \
  "settings changes are not written back to shell.json"
# Dropdowns write `value` imperatively on selection, which destroys a plain
# inline binding the first time a row is picked.
assert_contains $'Binding on value { value: String(root.setting("provider", "GitHub")) }' \
  "the provider dropdown does not re-assert the persisted value"
assert_contains $'Binding on value { value: svc.linkBehavior }' \
  "the open-links dropdown does not re-assert the persisted value"
assert_contains $'Binding on value { value: String(root.setting("repositoryScope", "Owned")) }' \
  "the repository scope dropdown does not re-assert the persisted value"
assert_contains 'options: root.term.scopeOptions' \
  "the repository scope dropdown does not use provider-specific option labels"
assert_contains 'onChanged: function(value) { root.persistSettings({ provider: value }) }' \
  "the provider dropdown does not persist its selection"
assert_contains 'providerDropdown.close()' \
  "closing the panel while the provider dropdown is open leaves it floating"
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
assert_contains $'title: "ASSIGNED ISSUES"\n            count: svc.assignedIssues.length\n            model: root.sectionRows(svc.assignedIssues, root.issuesExpanded)\n            expanded: root.issuesExpanded\n            footerButtonsBordered: true\n            openUrl: root.issuesUrl()' \
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

# Provider-conditional deep links and terminology.
assert_contains 'text: root.term.icon' \
  "the bar icon does not switch with the provider"
assert_contains 'title: svc.login !== "" ? root.term.name + " · " + svc.login : root.term.name' \
  "the hero title does not read as a provider-branded dashboard"
assert_contains 'svc.runCount + " active " + root.term.activeMetricLabel.toLowerCase()' \
  "the hero summary does not describe runs using the provider's own noun"
assert_contains 'title: root.term.myItemsTitle' \
  "the authored section is not renamed per the provider's own terminology"
assert_contains 'title: root.term.runningTitle' \
  "the active-runs section is not renamed per provider"
assert_contains 'title: root.term.failedTitle' \
  "the failed-runs section is not renamed per provider"
assert_contains 'openUrl: root.notificationsUrl()' \
  "the notifications section does not deep-link through the provider-aware helper"
assert_contains 'openUrl: root.reviewsUrl()' \
  "the review requests section does not deep-link through the provider-aware helper"
assert_contains $'return svc.provider === "gitlab" ? (svc.host || "https://gitlab.com") + "/dashboard/todos" : "https://github.com/notifications"' \
  "notificationsUrl does not fall back to the right default per provider"
assert_contains $'return svc.provider === "gitlab" ? (svc.host || "https://gitlab.com") + "/dashboard/merge_requests?reviewer_username=" + svc.login : "https://github.com/pulls/review-requested"' \
  "reviewsUrl does not resolve the GitLab username or the GitHub static URL"
assert_contains 'text: root.term.openInLabel' \
  "the section footer does not say Open in <provider>"
assert_contains 'svc.fetchedRepositoryScope === "owned" ? root.term.ownedRepoNounTitle : root.term.repoNounTitle' \
  "the repository heading does not follow the fetched scope"
assert_contains '"No " + root.term.repoNoun + " loaded."' \
  "the repository empty state does not use the provider's own noun"
assert_contains 'detail: modelData.repository + root.term.refPrefix + modelData.number' \
  "the authored row does not use the provider's own reference prefix"
assert_contains 'glyph: modelData.type === (svc.provider === "gitlab" ? "MergeRequest" : "PullRequest") ? root.term.itemGlyph : ' \
  "the notification glyph does not recognise the provider's own authored-item type"
assert_contains 'component RepositoryRow: CursorSurface' \
  "the provider-neutral repository row component was not unified"

echo "panel source tests passed"
