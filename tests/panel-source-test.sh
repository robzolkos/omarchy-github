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
assert_occurrences() {
  local needle=$1 expected=$2 message=$3 haystack=$PANEL_SOURCE count=0
  while [[ $haystack == *"$needle"* ]]; do
    haystack=${haystack#*"$needle"}
    count=$((count + 1))
  done
  [[ $count -eq $expected ]] || fail "$message (expected $expected, found $count)"
}

assert_contains 'glyph: broken ? "󰅖" : (running ? "󰑮" : (checks === "SUCCESS" ? "󰄬" : ""))' \
  "authored pull requests without checks do not use the pull request glyph"
assert_contains $'text: linkRow.title\n          textFormat: Text.PlainText' \
  "row titles are not forced to plain text"
assert_contains $'text: linkRow.detail\n          textFormat: Text.PlainText' \
  "row details are not forced to plain text"
assert_contains $'text: github.notificationActionStatus\n            textFormat: Text.PlainText' \
  "notification action status is not forced to plain text"
assert_contains $'return summary\n              }\n              textFormat: Text.PlainText' \
  "dashboard warning text is not forced to plain text"
assert_contains $'actionText: "Mark all read"\n            actionBusyText: "Marking…"\n            // Keep the displayed snapshot visible during refresh, but do not\n            // allow a destructive bulk action until that snapshot is current.\n            actionEnabled: github.state === "ready" && !github.loading\n            actionBusy: github.marking\n            actionRevision: github.notificationsRevision\n            actionPrepare: function() { return github.prepareMarkAllNotificationsRead() }\n            onActionTriggered: function(prepared) { github.markAllNotificationsRead(prepared) }' \
  "notification bulk action is not disabled while its displayed snapshot is refreshing"
assert_not_contains 'Refreshing dashboard' \
  "a ready summary is still replaced by Refreshing dashboard while a fetch runs"
assert_contains $'meta: github.state === "ready" ?\n              github.unreadCount + " unread · " + github.reviewRequests.length + " reviews · " + github.actionCount + " active actions"\n                + (github.failingPullRequestCount > 0 ? " · " + github.failingPullRequestCount + " failing" : "") : github.message' \
  "the hero summary is still gated on loading rather than the last ready snapshot"
assert_contains $'width: Style.space(22)\n                  height: Style.space(22)\n                  opacity: github.loading ? 1 : 0' \
  "the refresh spinner still collapses and shifts the gear"
assert_not_contains 'width: visible ? Style.space(22) : 0' \
  "the refresh spinner still collapses and shifts the gear"
assert_contains $'text: "󰑐"\n                    color: root.dim\n                    font.family: root.fontFamily\n                    font.pixelSize: Style.font.icon\n                    transformOrigin: Item.Center\n\n                    RotationAnimation on rotation {\n                      from: 0\n                      to: 360\n                      duration: 900\n                      loops: Animation.Infinite\n                      running: github.loading' \
  "a fetch in flight does not show a centered, continuously rotating spinner"
assert_contains $'hoverEnabled: github.loading\n                    enabled: github.loading\n                    acceptedButtons: Qt.NoButton\n\n                    PanelToolTip {\n                      visible: parent.containsMouse\n                      text: "Updating from GitHub"' \
  "the refresh spinner tooltip is not hover-only or intercepts clicks"
assert_contains $'visible: github.state !== "ready" || github.warnings.length > 0' \
  "first-load, error, and rate-limited status details are hidden"
assert_contains $'onActionBusyChanged: if (section.actionBusy) section.disarmAction()\n    onActionEnabledChanged: if (!section.actionEnabled) section.disarmAction()\n    onActionRevisionChanged: if (section.actionArmed) section.disarmAction()' \
  "bulk confirmation is not invalidated when notification state changes"
assert_contains $'var confirmed = section.preparedAction\n          section.disarmAction()\n          section.actionTriggered(confirmed)' \
  "bulk action does not submit the originally prepared snapshot"
assert_contains $'function activateCursor() {\n    if (!selectedTarget) return\n    openRow(selectedTarget.kind, selectedTarget.row.id, selectedTarget.row.url)' \
  "opening a notification from the keyboard does not mark it read"
assert_contains $'function openRow(kind, id, url) {\n    var target = String(url || "")\n    var notificationId = String(id || "")\n    openUrl(target)\n    if (kind === "notification") github.markNotificationRead(notificationId)' \
  "opening a notification marks it before launching the URL"
assert_contains $'function markSelectedRead() {\n    if (selectedTarget && selectedTarget.kind === "notification") github.markNotificationRead(String(selectedTarget.row.id || ""))' \
  "keyboard notification marking is blocked during refresh"
assert_contains $'onClicked: root.openRow(linkRow.rowKind, linkRow.notificationId || linkRow.rowId, linkRow.url)' \
  "clicking a notification does not open and mark it read"
assert_contains $'if (github.linkBehavior === "Browser tab") Util.execArgv(["xdg-open", value])\n    else Quickshell.execDetached(["omarchy-launch-webapp", value])' \
  "the open-links setting does not choose between the browser and the web app window"

# updateEntryInline rewrites the shell.json entry whole, so a persist that does
# not carry the current settings forward silently drops every other setting.
assert_contains $'var entry = { id: root.moduleName }\n    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]' \
  "persisting a setting does not merge the entry from the current settings"
assert_contains 'root.bar.shell.updateEntryInline(root.moduleName, entry)' \
  "settings changes are not written back to shell.json"
# Dropdown writes `value` imperatively on selection, which destroys a plain
# inline binding the first time a row is picked.
assert_contains $'Binding on value { value: github.linkBehavior }' \
  "the open-links dropdown does not re-assert the persisted value"
assert_contains 'blocked: root.settingsOpen || search.activeFocus' \
  "the key catcher steals keys from the settings controls"
assert_contains 'visible: !root.settingsOpen' \
  "the dashboard stays visible behind the settings page"
assert_contains 'visible: root.settingsOpen' \
  "the settings page is always visible"
assert_contains $'pageFlip.stop()\n      settingsOpen = false' \
  "closing the panel leaves it on the settings page"
assert_contains $'linkBehaviorDropdown.close()\n    repositoryScopeDropdown.close()\n    refreshIntervalDropdown.close()\n    contributionsPositionDropdown.close()\n    if (sortPicker) sortPicker.close()' \
  "leaving settings does not close every settings dropdown"
assert_contains $'id: readActionStrip\n      visible: linkRow.showReadAction\n      anchors.right: parent.right\n      anchors.top: parent.top\n      anchors.bottom: parent.bottom\n      width: Style.space(32)' \
  "notification read target does not fill the row height at its right edge"
assert_contains $'anchors.right: readActionStrip.visible ? readActionStrip.left : parent.right\n      anchors.verticalCenter: parent.verticalCenter\n      anchors.leftMargin: Style.space(9)\n      anchors.rightMargin: readActionStrip.visible ? 0 : Style.space(9)' \
  "notification content does not meet the full-height read target"
assert_contains $'borderSpec: Border.none()\n\n      HoverHandler {\n        onHoveredChanged: if (hovered) root.selectKey(linkRow.cursorKey)\n      }\n\n      Rectangle {\n        anchors.left: parent.left\n        anchors.top: parent.top\n        anchors.bottom: parent.bottom' \
  "notification read target does not use a left-only divider"
assert_contains $'anchors.fill: parent\n        enabled: github.markingNotificationId !== linkRow.notificationId' \
  "notification read target does not fill its action strip"
assert_contains $'function notificationRows() {\n    var page = Math.max(0, Math.min(notificationsPage, notificationPageCount() - 1))' \
  "notifications are not paged in five-item windows"
assert_contains $'onPreviousPage: root.notificationsPage = Math.max(0, root.notificationsPage - 1)\n            onNextPage: root.notificationsPage = Math.min(root.notificationPageCount() - 1, root.notificationsPage + 1)' \
  "notification page controls do not clamp their range"
assert_contains $'model: root.notificationRows()\n            showExpansionControl: false\n            footerButtonsBordered: true\n            page: root.notificationsPage' \
  "notification pagination still shows an inactive expansion control"
assert_contains $'showReadAction: true\n      showTrailingIndicator: false\n      notificationId: String(modelData.id || "")' \
  "notification rows retain an open-link indicator beside their read action"
assert_contains $'title: "ASSIGNED ISSUES"\n            count: github.assignedIssues.length\n            model: root.sectionRows(github.assignedIssues, root.issuesExpanded)\n            expanded: root.issuesExpanded\n            footerButtonsBordered: true\n            openUrl: "https://github.com/issues/assigned"' \
  "assigned-issues open control does not retain its matching border"
assert_contains 'readonly property bool showAction: section.count > 0 && section.actionText !== ""' \
  "bulk notification action disappears while data is loading"
assert_contains 'enabled: section.actionEnabled && !section.actionBusy' \
  "bulk notification action is not disabled until it is ready"
assert_contains $'text: "󰅁"\n        tooltipText: "Previous notifications"' \
  "previous notification page control is missing"
assert_contains $'text: "󰅂"\n        tooltipText: "Next notifications"' \
  "next notification page control is missing"
assert_contains $'text: (section.page + 1) + " / " + section.pageCount\n        height: previousPageButton.height\n        color: root.dim' \
  "notification page number is not vertically centered with its controls"

assert_contains $'function applyPanelWheel(event) {\n    if (!panelFlick || (sortPicker && sortPicker.popupOpen)) return false' \
  "the panel still uses Flickable's default wheel distance"
assert_contains $'panelFlick.contentY = Math.max(0, Math.min(maxY, panelFlick.contentY - wheel.steps * Style.space(80)))' \
  "a mouse-wheel notch does not move about one row"
assert_contains $'ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }\n        // Must be a direct child of Flickable or Qt keeps the default\n        // 1–2px wheel distance and this handler never runs.\n        WheelHandler {\n          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad' \
  "the wheel handler is not a direct child of the panel Flickable"

assert_contains 'github.fetchedRepositoryScope === "owned" ? "OWNED REPOSITORIES  " : "REPOSITORIES  "' \
  "the repository heading does not follow the fetched scope"
assert_contains '"No repositories loaded."' \
  "the repository empty state still claims a scope"

# The contributions block derives its alpha ramp from the theme foreground so
# the heatmap shades correctly under every theme. Anchoring on a hardcoded
# palette would silently break light themes and the dim mode.
assert_contains $'Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, shadeAlpha(level))' \
  "contribution cells do not anchor their shading on the theme foreground"
assert_occurrences 'ContributionsBlock {' 1 \
  "the panel does not use one shared contribution calendar component"
assert_contains $'Component {\n    id: contributionsBlockComponent\n    ContributionsBlock {\n      days: github.contributions.days\n      total: github.contributions.total\n      login: github.login' \
  "the shared contribution calendar does not bind to the helper output"
assert_contains 'readonly property bool hasContributionCalendar: Array.isArray(github.contributions.days) && github.contributions.days.length > 0' \
  "empty contribution payloads do not collapse the contribution section"
assert_contains 'active: github.includeContributions' \
  "contributions loaders do not honour the includeContributions setting"
assert_contains 'width: gridWidth' \
  "contributions grid does not own its own width"
assert_contains 'anchors.horizontalCenter: parent.horizontalCenter' \
  "contributions grid does not center inside the block"
assert_contains $'delegate: Rectangle {\n                id: dayCell\n                required property var modelData' \
  "contribution day delegates do not expose their model data to the tooltip"
assert_contains 'visible: dayMouse.containsMouse && String(dayCell.modelData.date || "") !== ""' \
  "contribution tooltips do not read visibility from the day delegate"
assert_contains 'var date = String(dayCell.modelData.date || "")' \
  "contribution tooltips do not read the date from the day delegate"
assert_contains 'var count = Number(dayCell.modelData.count || 0)' \
  "contribution tooltips do not read the count from the day delegate"
assert_not_contains 'parent.modelData' \
  "contribution tooltips still read model data from their MouseArea parent"
# A populated calendar can legitimately report a zero annual total. Its header
# must show that API total rather than substituting the number of day cells.
assert_contains 'text: "CONTRIBUTIONS  " + Number(total).toLocaleString(Qt.locale(), "f", 0)' \
  "zero-total populated calendars do not display the reported total"
assert_not_contains 'total > 0 ? Number(total).toLocaleString(Qt.locale(), "f", 0) : dayCount' \
  "contribution header substitutes the populated day count for a zero total"
assert_not_contains $'text: "GITHUB CONTRIBUTIONS"' \
  "old GITHUB CONTRIBUTIONS heading was not removed"
assert_not_contains $'text: "POSITION"' \
  "short POSITION label still present"
assert_contains $'text: "Contributions Position"' \
  "contributions position heading is missing or mislabelled"
assert_contains $'label: "Show contribution calendar"' \
  "include-contributions toggle is not in the contributions section"
assert_contains $'options: root.contributionsPositionOptions' \
  "contributions position dropdown does not bind to its option list"
assert_contains 'onClicked: root.persistSettings({ includeContributions: !github.includeContributions })' \
  "include-contributions toggle does not persist its new value"
assert_contains $'onChanged: function(value) { root.persistSettings({ contributionsPosition: value }) }' \
  "contributions position dropdown does not persist its new value"
# Loaders keep each placement in the dashboard flow while only the selected
# slot instantiates the shared calendar tree. Qt retains a Loader's former
# implicit height after deactivation, so inactive slots must explicitly be
# zero-height or they leave a calendar-sized blank region in the Column.
assert_contains $'Loader {\n            id: contributionsBlockTop\n            width: parent.width\n            active: github.includeContributions && root.hasContributionCalendar && github.contributionsPosition === "Top"\n            visible: active\n            height: active ? implicitHeight : 0\n            sourceComponent: contributionsBlockComponent' \
  "top contributions slot does not conditionally load the shared calendar"
assert_contains $'Loader {\n            id: contributionsBlockMiddle\n            width: parent.width\n            active: github.includeContributions && root.hasContributionCalendar && github.contributionsPosition === "Middle (above repositories)"\n            visible: active\n            height: active ? implicitHeight : 0\n            sourceComponent: contributionsBlockComponent' \
  "middle contributions slot does not conditionally load the shared calendar"
assert_contains $'Loader {\n            id: contributionsBlockBottom\n            width: parent.width\n            active: github.includeContributions && root.hasContributionCalendar && github.contributionsPosition === "Bottom"\n            visible: active\n            height: active ? implicitHeight : 0\n            sourceComponent: contributionsBlockComponent' \
  "bottom contributions slot does not conditionally load the shared calendar"
assert_occurrences 'sourceComponent: contributionsBlockComponent' 3 \
  "all contribution placements do not use the shared calendar component"
assert_occurrences 'visible: active' 3 \
  "inactive contribution placements remain visible"
assert_occurrences 'height: active ? implicitHeight : 0' 3 \
  "inactive contribution placements still reserve blank dashboard space"

echo "panel source tests passed"
