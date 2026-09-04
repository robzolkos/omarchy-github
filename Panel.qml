import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "robzolkos.github"
  ipcTarget: "robzolkos.github"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property string query: ""
  property string metricFilter: "all"
  property string sortMode: "updated"
  property bool cursorActive: false
  property int cursorIndex: 0
  property int notificationsPage: 0
  property bool reviewsExpanded: false
  property bool authoredExpanded: false
  property bool issuesExpanded: false
  property bool runsExpanded: false
  property bool failuresExpanded: false
  // settingsOpen is the page on screen; pendingSettingsOpen is the page the
  // in-flight flip will land on, since the swap happens edge-on at 90 degrees.
  property bool settingsOpen: false
  property bool pendingSettingsOpen: false
  readonly property var providerOptions: [
    { value: "GitHub", label: "GitHub" },
    { value: "GitLab", label: "GitLab" }
  ]
  readonly property var linkBehaviorOptions: [
    { value: "Web app window", label: "Web app window" },
    { value: "Browser tab", label: "Browser tab" }
  ]
  readonly property var refreshIntervalOptions: [
    { value: "300", label: "Every 5 minutes" },
    { value: "600", label: "Every 10 minutes" },
    { value: "900", label: "Every 15 minutes" },
    { value: "1800", label: "Every 30 minutes" },
    { value: "3600", label: "Every hour" }
  ]
  // Every string and icon that differs between providers lives here, so the
  // rest of the panel reads root.term.xxx instead of branching on provider
  // itself. The two providers otherwise share this file's structure exactly.
  readonly property var githubTerms: ({
    name: "GitHub",
    icon: "",
    itemGlyph: "",
    refPrefix: " #",
    myItemsTitle: "MY PULL REQUESTS",
    runningTitle: "RUNNING ACTIONS",
    failedTitle: "RECENT FAILED ACTIONS",
    itemFilterLabel: "PRs",
    activeMetricLabel: "Actions",
    repoNoun: "repositories",
    repoNounTitle: "REPOSITORIES",
    ownedRepoNounTitle: "OWNED REPOSITORIES",
    filterPlaceholder: "Filter repositories  /",
    scopeOptions: [
      { value: "Owned", label: "Owned repositories" },
      { value: "Wider", label: "Owned and organizations" }
    ],
    archivedDesc: "Show repositories that have been archived on GitHub.",
    forksDesc: "Show repositories you forked from someone else.",
    unlitDesc: "Leave the icon dim even when notifications, reviews, or failing actions are waiting.",
    remainingOptionsText: "The remaining options — Actions scanning, review request filters, and display limits — stay in Omarchy's bar widget settings.",
    openInLabel: "Open in GitHub  󰅂"
  })
  readonly property var gitlabTerms: ({
    name: "GitLab",
    icon: "󰮠",
    itemGlyph: "󰘭",
    refPrefix: " !",
    myItemsTitle: "MY MERGE REQUESTS",
    runningTitle: "RUNNING PIPELINES",
    failedTitle: "RECENT FAILED PIPELINES",
    itemFilterLabel: "MRs",
    activeMetricLabel: "Pipelines",
    repoNoun: "projects",
    repoNounTitle: "PROJECTS",
    ownedRepoNounTitle: "OWNED PROJECTS",
    filterPlaceholder: "Filter projects  /",
    scopeOptions: [
      { value: "Owned", label: "Owned projects" },
      { value: "Wider", label: "Member of" }
    ],
    archivedDesc: "Show projects that have been archived on GitLab.",
    forksDesc: "Show projects you forked from someone else.",
    unlitDesc: "Leave the icon dim even when notifications, reviews, or failing pipelines are waiting.",
    remainingOptionsText: "The remaining options — pipeline scanning, review request filters, and display limits — stay in Omarchy's bar widget settings.",
    openInLabel: "Open in GitLab  󰅂"
  })
  readonly property var term: svc.provider === "gitlab" ? gitlabTerms : githubTerms
  // Carry sub-notch wheel deltas between events. Touchpads emit many small
  // angleDeltas; mice often emit a fake 1–2px pixelDelta that would otherwise
  // crawl the dashboard a couple of pixels per click.
  property real wheelAccumulator: 0
  readonly property int activityPreviewCount: 5
  readonly property int activityExpandedCount: 25
  readonly property var metricFilters: [
    { id: "all", label: "All" }, { id: "issues", label: "Issues" },
    { id: "prs", label: root.term.itemFilterLabel }, { id: "stars", label: "Stars" },
    { id: "runs", label: root.term.activeMetricLabel }
  ]
  readonly property var sortModes: [
    { value: "updated", label: "Updated" }, { value: "name", label: "Name" },
    { value: "stars", label: "Stars" }, { value: "issues", label: "Issues" },
    { value: "prs", label: root.term.itemFilterLabel }, { value: "runs", label: root.term.activeMetricLabel }
  ]
  readonly property var displayedRepositories: filteredRepositories()
  readonly property var cursorTargets: buildCursorTargets()
  readonly property var selectedTarget: cursorTargets.length > 0 ? cursorTargets[Math.max(0, Math.min(cursorIndex, cursorTargets.length - 1))] : null

  function sectionRows(rows, expanded) {
    return rows.slice(0, expanded ? activityExpandedCount : activityPreviewCount)
  }

  function notificationPageCount() {
    return Math.max(1, Math.ceil(svc.notifications.length / activityPreviewCount))
  }

  function notificationRows() {
    var page = Math.max(0, Math.min(notificationsPage, notificationPageCount() - 1))
    if (page !== notificationsPage) notificationsPage = page
    var start = page * activityPreviewCount
    return svc.notifications.slice(start, start + activityPreviewCount)
  }

  function buildCursorTargets() {
    var targets = []
    function add(kind, rows) {
      for (var i = 0; i < rows.length; i++) targets.push({ key: kind + ":" + String(rows[i].id || rows[i].url || i), kind: kind, row: rows[i] })
    }
    add("notification", notificationRows())
    add("review", sectionRows(svc.reviewRequests, reviewsExpanded))
    add("authored", sectionRows(svc.authored, authoredExpanded))
    add("issue", sectionRows(svc.assignedIssues, issuesExpanded))
    add("run", sectionRows(svc.runs, runsExpanded))
    add("failedrun", sectionRows(svc.failedRuns, failuresExpanded))
    add("repo", displayedRepositories)
    return targets
  }

  function targetKey(kind, row, index) { return kind + ":" + String((row && (row.id || row.url)) || index) }
  function selectedKey() { return selectedTarget ? selectedTarget.key : "" }
  function selectKey(key) {
    for (var i = 0; i < cursorTargets.length; i++) if (cursorTargets[i].key === key) { cursorActive = true; cursorIndex = i; return }
  }
  function ensureCursor() {
    if (cursorTargets.length === 0) { cursorIndex = 0; return }
    cursorIndex = Math.max(0, Math.min(cursorIndex, cursorTargets.length - 1))
  }
  function moveCursor(delta) {
    cursorActive = true
    if (cursorTargets.length === 0) return
    cursorIndex = Math.max(0, Math.min(cursorTargets.length - 1, cursorIndex + delta))
  }
  function activateCursor() {
    if (!selectedTarget) return
    openRow(selectedTarget.kind, selectedTarget.row.id, selectedTarget.row.url)
  }
  // Snapshot id/url before marking. hideNotification destroys the row, and
  // reading linkRow.url after that leaves openUrl with an empty target.
  function openRow(kind, id, url) {
    var target = String(url || "")
    var notificationId = String(id || "")
    openUrl(target)
    if (kind === "notification") svc.markNotificationRead(notificationId)
  }
  function markSelectedRead() {
    if (selectedTarget && selectedTarget.kind === "notification") svc.markNotificationRead(String(selectedTarget.row.id || ""))
  }
  function applyPanelWheel(event) {
    if (!panelFlick || (sortPicker && sortPicker.popupOpen)) return false
    var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
    if (maxY <= 0) return false
    var pixel = event.pixelDelta.y
    var angle = event.angleDelta.y
    var wheel = Util.wheelSteps(root.wheelAccumulator, angle)
    root.wheelAccumulator = wheel.remainder
    // A mouse notch is 120°. Move about one dashboard row per notch.
    if (wheel.steps !== 0) {
      panelFlick.contentY = Math.max(0, Math.min(maxY, panelFlick.contentY - wheel.steps * Style.space(80)))
      return true
    }
    // Touchpads report a real pixelDelta larger than Qt's angle conversion.
    // Scale it so two-finger scroll matches the notch distance above.
    if (pixel !== 0 && Math.abs(pixel) > Math.abs(angle) / 8) {
      root.wheelAccumulator = 0
      panelFlick.contentY = Math.max(0, Math.min(maxY, panelFlick.contentY - pixel * 3))
      return true
    }
    // Swallow leftover high-res angle crumbs so Flickable cannot crawl 1–2px.
    return angle !== 0 || pixel !== 0
  }
  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var margin = Style.space(8)
      var top = point.y
      var bottom = top + item.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function checkLabel(checks) {
    if (checks === "SUCCESS") return "checks passing"
    if (checks === "ERROR") return "checks errored"
    if (svc.isBrokenCheck(checks)) return "checks failing"
    if (svc.isRunningCheck(checks)) return "checks running"
    return "no checks"
  }

  function openUrl(url) {
    var value = String(url || "")
    if (value === "") return
    // omarchy-launch-webapp gives the forge its own window; omarchy-launch-browser
    // hands the URL to the default browser for those without a Chromium-based one.
    if (svc.linkBehavior === "Browser tab") Quickshell.execDetached(["omarchy-launch-browser", value])
    else Quickshell.execDetached(["omarchy-launch-webapp", value])
    close()
  }

  // Settings live on this widget's entry in shell.json; the shell hot-reloads
  // the file and every instance sees the new value. Applied locally first so
  // the control moves on the click, and the entry is merged from the current
  // settings because updateEntryInline replaces it whole.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) {
      if (values[key] === undefined) delete entry[key]
      else entry[key] = values[key]
    }
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function showSettings(open) {
    var next = open === true
    if (settingsOpen === next || pageFlip.running) return
    pendingSettingsOpen = next
    // A popup left open would float over the card while it flips.
    providerDropdown.close()
    linkBehaviorDropdown.close()
    repositoryScopeDropdown.close()
    refreshIntervalDropdown.close()
    if (sortPicker) sortPicker.close()
    pageFlip.restart()
  }

  function filteredRepositories() {
    var needle = String(query || "").trim().toLowerCase()
    var rows = []
    for (var i = 0; i < svc.repositories.length; i++) {
      var repo = svc.repositories[i]
      if (needle !== "" && String(repo.nameWithOwner || repo.name || "").toLowerCase().indexOf(needle) === -1) continue
      if (metricFilter === "issues" && Number(repo.issues || 0) <= 0) continue
      if (metricFilter === "prs" && Number(repo.prs || 0) <= 0) continue
      if (metricFilter === "stars" && Number(repo.stars || 0) <= 0) continue
      if (metricFilter === "runs" && Number(repo.activeRuns || 0) <= 0) continue
      rows.push(repo)
    }
    rows.sort(function(a, b) {
      if (sortMode === "name") return String(a.nameWithOwner).localeCompare(String(b.nameWithOwner))
      if (sortMode === "updated") return String(b.updatedAt).localeCompare(String(a.updatedAt))
      var av = Number(a[sortMode] || (sortMode === "runs" ? a.activeRuns : 0) || 0)
      var bv = Number(b[sortMode] || (sortMode === "runs" ? b.activeRuns : 0) || 0)
      if (av !== bv) return bv - av
      return String(a.nameWithOwner).localeCompare(String(b.nameWithOwner))
    })
    return rows.slice(0, Math.max(10, Number(setting("maxDisplayedRepositories", 25))))
  }

  function relativeTime(value) {
    var then = new Date(String(value || "")).getTime()
    if (!isFinite(then)) return ""
    var seconds = Math.max(0, Math.floor((Date.now() - then) / 1000))
    if (seconds < 60) return "just now"
    if (seconds < 3600) return Math.floor(seconds / 60) + "m ago"
    if (seconds < 86400) return Math.floor(seconds / 3600) + "h ago"
    if (seconds < 2592000) return Math.floor(seconds / 86400) + "d ago"
    return Math.floor(seconds / 2592000) + "mo ago"
  }

  // Static per-provider defaults; svc.host is authoritative once a payload
  // has actually been fetched but is empty until then.
  function notificationsUrl() {
    return svc.provider === "gitlab" ? (svc.host || "https://gitlab.com") + "/dashboard/todos" : "https://github.com/notifications"
  }
  function reviewsUrl() {
    return svc.provider === "gitlab" ? (svc.host || "https://gitlab.com") + "/dashboard/merge_requests?reviewer_username=" + svc.login : "https://github.com/pulls/review-requested"
  }
  function myItemsUrl() {
    return svc.provider === "gitlab" ? (svc.host || "https://gitlab.com") + "/dashboard/merge_requests?author_username=" + svc.login : "https://github.com/pulls"
  }
  function issuesUrl() {
    return svc.provider === "gitlab" ? (svc.host || "https://gitlab.com") + "/dashboard/issues?assignee_username=" + svc.login : "https://github.com/issues/assigned"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    // A pending confirmation must never survive the panel closing, or the next
    // open would run a destructive action on a single click.
    if (notificationsSection) notificationsSection.disarmAction()
    if (!opened) {
      // Never reopen mid-flip or on a page the user cannot see themselves onto.
      pageFlip.stop()
      settingsOpen = false
      pendingSettingsOpen = false
      cardRotation.angle = 0
    }
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      if (panelFlick) panelFlick.contentY = 0
      svc.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }
  onCursorTargetsChanged: ensureCursor()

  Service { id: svc; settings: root.settings }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { svc.refresh(); return "ok" }
    function status(): string { return svc.state }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.term.icon
    active: svc.alarming
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) svc.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(root.settingsOpen
      ? settingsHeader.implicitHeight + settingsContent.implicitHeight + Style.space(24)
      : content.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Settings controls own their native focus chain and keys. The settings
      // page carries its own Escape handler to return to the dashboard.
      blocked: root.settingsOpen || search.activeFocus || sortPicker.popupOpen
      onMoveRequested: function(dx, dy) { if (root.settingsOpen) return; if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: if (!root.settingsOpen) root.activateCursor()
      onCloseRequested: if (root.settingsOpen) root.showSettings(false); else root.close()
      // Tab enters the native control chain so search, filters, sorting, and
      // section controls remain keyboard-accessible.
      onTabRequested: function(direction) {
        if (root.settingsOpen) return
        if (direction < 0) sortPicker.forceActiveFocus()
        else search.forceActiveFocus()
      }
      onTextKey: function(text) {
        if (root.settingsOpen) return
        if (text === "r" || text === "R") svc.refresh()
        else if (text === "/") Qt.callLater(function() { search.forceActiveFocus() })
        else if (text === "m" || text === "M") root.markSelectedRead()
      }

      // Rotating the key catcher flips both pages together as one card.
      transform: Rotation {
        id: cardRotation
        origin.x: keyCatcher.width / 2
        origin.y: keyCatcher.height / 2
        axis.x: 0
        axis.y: 1
        axis.z: 0
      }

      SequentialAnimation {
        id: pageFlip

        NumberAnimation { target: cardRotation; property: "angle"; from: 0; to: 90; duration: 130; easing.type: Easing.InQuad }
        ScriptAction {
          script: {
            root.settingsOpen = root.pendingSettingsOpen
            cardRotation.angle = -90
            if (root.settingsOpen && settingsFlick) settingsFlick.contentY = 0
          }
        }
        NumberAnimation { target: cardRotation; property: "angle"; from: -90; to: 0; duration: 170; easing.type: Easing.OutQuad }
        ScriptAction {
          // Focus lands on the first setting so Tab walks forward through the
          // form, and Qt.callLater waits for the visibility pass to finish.
          script: Qt.callLater(function() {
            if (root.settingsOpen) providerDropdown.forceActiveFocus()
            else keyCatcher.forceActiveFocus()
          })
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        visible: !root.settingsOpen
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        // Must be a direct child of Flickable or Qt keeps the default
        // 1–2px wheel distance and this handler never runs.
        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          orientation: Qt.Vertical
          grabPermissions: PointerHandler.CanTakeOverFromAnything
          onWheel: function(event) {
            if (root.applyPanelWheel(event)) event.accepted = true
          }
        }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: svc.login !== "" ? root.term.name + " · " + svc.login : root.term.name
            // Mirrors every term of the alarming state, so the summary always
            // explains why the bar icon is lit.
            meta: svc.loading ? "Refreshing dashboard…" : (svc.state === "ready" ?
              svc.unreadCount + " unread · " + svc.reviewRequests.length + " reviews · " + svc.runCount + " active " + root.term.activeMetricLabel.toLowerCase()
                + (svc.failingAuthoredCount > 0 ? " · " + svc.failingAuthoredCount + " failing" : "") : svc.message)
            foreground: root.foreground
            fontFamily: root.fontFamily
            // The hero reserves the trailing space and centres the control
            // against the labels, so the gear needs no geometry of its own.
            trailingControl: Component {
              PanelActionButton {
                iconText: "󰒓"
                tooltipText: root.term.name + " settings"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.showSettings(true)
              }
            }
            iconComponent: Component {
              Text {
                text: root.term.icon
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }
            }
          }

          Text {
            visible: svc.notificationActionStatus !== ""
            width: parent.width
            text: svc.notificationActionStatus
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          BorderSurface {
            visible: svc.state !== "ready" || svc.warnings.length > 0
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.space(20)
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10)
            borderSpec: Border.flat(Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              text: {
                if (svc.state !== "ready") return svc.message
                var summary = "Partial results · " + String(svc.warnings[0] || "A request failed.")
                if (svc.warnings.length > 1) summary += " · " + (svc.warnings.length - 1) + " more"
                return summary
              }
              textFormat: Text.PlainText
              color: svc.state === "ready" ? root.dim : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          DashboardSection {
            id: notificationsSection
            title: "UNREAD NOTIFICATIONS"
            count: svc.notifications.length
            emptyText: svc.state === "ready" ? "You're all caught up." : "No notifications loaded."
            model: root.notificationRows()
            showExpansionControl: false
            footerButtonsBordered: true
            page: root.notificationsPage
            pageCount: root.notificationPageCount()
            openUrl: root.notificationsUrl()
            onPreviousPage: root.notificationsPage = Math.max(0, root.notificationsPage - 1)
            onNextPage: root.notificationsPage = Math.min(root.notificationPageCount() - 1, root.notificationsPage + 1)
            delegateComponent: notificationDelegate
            actionText: "Mark all read"
            actionBusyText: "Marking…"
            actionEnabled: svc.state === "ready" && !svc.loading
            actionBusy: svc.marking
            actionRevision: svc.notificationsRevision
            actionPrepare: function() { return svc.prepareMarkAllNotificationsRead() }
            onActionTriggered: function(prepared) { svc.markAllNotificationsRead(prepared) }
          }

          DashboardSection {
            visible: count > 0
            title: "REVIEW REQUESTS"
            count: svc.reviewRequests.length
            model: root.sectionRows(svc.reviewRequests, root.reviewsExpanded)
            expanded: root.reviewsExpanded
            openUrl: root.reviewsUrl()
            onToggleExpanded: root.reviewsExpanded = !root.reviewsExpanded
            delegateComponent: reviewDelegate
          }

          DashboardSection {
            visible: count > 0
            title: root.term.myItemsTitle
            // The query is capped at one page, so the fetched list can be
            // shorter than the real total. Show the total rather than implying
            // the section is complete.
            count: Math.max(svc.authoredTotal, svc.authored.length)
            model: root.sectionRows(svc.authored, root.authoredExpanded)
            expanded: root.authoredExpanded
            openUrl: root.myItemsUrl()
            onToggleExpanded: root.authoredExpanded = !root.authoredExpanded
            delegateComponent: authoredDelegate
          }

          DashboardSection {
            visible: count > 0
            title: "ASSIGNED ISSUES"
            count: svc.assignedIssues.length
            model: root.sectionRows(svc.assignedIssues, root.issuesExpanded)
            expanded: root.issuesExpanded
            footerButtonsBordered: true
            openUrl: root.issuesUrl()
            onToggleExpanded: root.issuesExpanded = !root.issuesExpanded
            delegateComponent: issueDelegate
          }

          DashboardSection {
            visible: count > 0
            title: root.term.runningTitle
            count: svc.runs.length
            model: root.sectionRows(svc.runs, root.runsExpanded)
            expanded: root.runsExpanded
            onToggleExpanded: root.runsExpanded = !root.runsExpanded
            delegateComponent: runDelegate
          }

          DashboardSection {
            visible: count > 0
            title: root.term.failedTitle
            count: svc.failedRuns.length
            model: root.sectionRows(svc.failedRuns, root.failuresExpanded)
            expanded: root.failuresExpanded
            onToggleExpanded: root.failuresExpanded = !root.failuresExpanded
            delegateComponent: failedRunDelegate
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            width: parent.width
            // Driven by the fetched scope, not the setting, so it cannot claim
            // to list the wider scope before a refresh brings it in.
            text: (svc.fetchedRepositoryScope === "owned" ? root.term.ownedRepoNounTitle : root.term.repoNounTitle) + "  " + root.displayedRepositories.length + "/" + svc.repositories.length
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          TextField {
            id: search
            width: parent.width
            foreground: root.foreground
            placeholderText: root.term.filterPlaceholder
            text: root.query
            onTextChanged: root.query = text
            Keys.onEscapePressed: function(event) {
              root.query = ""
              keyCatcher.forceActiveFocus()
              event.accepted = true
            }
          }

          Flickable {
            width: parent.width
            height: filterRow.implicitHeight
            contentWidth: filterRow.implicitWidth
            contentHeight: height
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            interactive: contentWidth > width
            Row {
              id: filterRow
              spacing: Style.space(6)
              Repeater {
                model: root.metricFilters
                Button {
                  required property var modelData
                  text: modelData.label
                  selected: root.metricFilter === modelData.id
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: root.metricFilter = modelData.id
                }
              }
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)
            Text {
              text: "Sort"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Dropdown {
              id: sortPicker
              Layout.fillWidth: true
              Binding on value { value: root.sortMode }
              options: root.sortModes
              showLabel: false
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(v) { root.sortMode = v }
            }
          }

          Text {
            visible: root.displayedRepositories.length === 0
            width: parent.width
            text: svc.repositories.length === 0 ? "No " + root.term.repoNoun + " loaded." : "No " + root.term.repoNoun + " match these filters."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: root.displayedRepositories
              RepositoryRow {
                required property var modelData
                required property int index
                width: parent.width
                repo: modelData
                rowIndex: index
              }
            }
          }

          Text {
            visible: svc.rateLimit && svc.rateLimit.remaining !== undefined
            width: parent.width
            text: "API requests remaining: " + (svc.rateLimit ? svc.rateLimit.remaining : "") +
              (svc.fetchedAt !== "" ? " · updated " + root.relativeTime(svc.fetchedAt) : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }

      ColumnLayout {
        id: settingsPage
        anchors.fill: parent
        visible: root.settingsOpen
        spacing: Style.space(12)
        // AfterItem so an open dropdown consumes the first Escape to close
        // itself, and only the next one returns to the dashboard.
        Keys.priority: Keys.AfterItem
        Keys.onEscapePressed: function(event) {
          root.showSettings(false)
          event.accepted = true
        }

        Column {
          id: settingsHeader
          Layout.fillWidth: true
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(settingsBackButton.implicitHeight, settingsLabels.implicitHeight)

            PanelActionButton {
              id: settingsBackButton
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰁍"
              tooltipText: "Back to the dashboard"
              foreground: root.foreground
              focusable: true
              fontFamily: root.fontFamily
              onClicked: root.showSettings(false)
            }

            Column {
              id: settingsLabels
              anchors.left: settingsBackButton.right
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                text: root.term.name.toUpperCase() + " SETTINGS"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }
        }

        Flickable {
          id: settingsFlick
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: settingsContent.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: settingsContent
            width: settingsFlick.width
            spacing: Style.space(20)

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "PROVIDER"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Dropdown {
                id: providerDropdown
                width: parent.width
                showLabel: false
                options: root.providerOptions
                foreground: root.foreground
                background: Color.popups.background
                accent: Color.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { root.persistSettings({ provider: value }) }

                Binding on value { value: String(root.setting("provider", "GitHub")) }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "OPEN LINKS"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Dropdown {
                id: linkBehaviorDropdown
                width: parent.width
                showLabel: false
                options: root.linkBehaviorOptions
                foreground: root.foreground
                background: Color.popups.background
                accent: Color.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { root.persistSettings({ linkBehavior: value }) }

                // Binding element (not an inline binding) so it survives the
                // imperative `value` write Dropdown makes on selection.
                Binding on value { value: svc.linkBehavior }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "REPOSITORY SCOPE"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Dropdown {
                id: repositoryScopeDropdown
                width: parent.width
                showLabel: false
                options: root.term.scopeOptions
                foreground: root.foreground
                background: Color.popups.background
                accent: Color.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { root.persistSettings({ repositoryScope: value }) }

                Binding on value { value: String(root.setting("repositoryScope", "Owned")) }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "REFRESH INTERVAL"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Dropdown {
                id: refreshIntervalDropdown
                width: parent.width
                showLabel: false
                options: root.refreshIntervalOptions
                foreground: root.foreground
                background: Color.popups.background
                accent: Color.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { root.persistSettings({ refreshIntervalSec: parseInt(value, 10) }) }

                // Dropdown values are strings, so the integer round-trips.
                Binding on value { value: String(root.setting("refreshIntervalSec", 900)) }
              }
            }

            PanelSeparator {
              width: parent.width
              foreground: root.foreground
            }

            Toggle {
              width: parent.width
              label: "Keep the bar icon unlit"
              description: root.term.unlitDesc
              checked: svc.iconAlwaysUnlit
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ iconAlwaysUnlit: !svc.iconAlwaysUnlit })
            }

            Toggle {
              width: parent.width
              label: "Include archived " + root.term.repoNoun
              description: root.term.archivedDesc
              checked: root.setting("includeArchived", false) === true
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ includeArchived: !(root.setting("includeArchived", false) === true) })
            }

            Toggle {
              width: parent.width
              label: "Include forked " + root.term.repoNoun
              description: root.term.forksDesc
              checked: root.setting("includeForks", false) === true
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ includeForks: !(root.setting("includeForks", false) === true) })
            }

            Text {
              width: parent.width
              text: root.term.remainingOptionsText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }

  Component {
    id: notificationDelegate
    LinkRow {
      required property var modelData
      required property int index
      width: parent ? parent.width : 0
      rowKind: "notification"
      rowIndex: index
      rowId: String(modelData.id || modelData.url || index)
      glyph: modelData.type === (svc.provider === "gitlab" ? "MergeRequest" : "PullRequest") ? root.term.itemGlyph : "󰍩"
      title: modelData.title
      detail: modelData.repository + " · " + modelData.reason + " · " + root.relativeTime(modelData.updatedAt)
      url: modelData.url
      showReadAction: true
      showTrailingIndicator: false
      notificationId: String(modelData.id || "")
    }
  }

  Component {
    id: reviewDelegate
    LinkRow {
      required property var modelData
      required property int index
      width: parent ? parent.width : 0
      rowKind: "review"
      rowIndex: index
      rowId: String(modelData.id || modelData.url || index)
      glyph: root.term.itemGlyph
      title: modelData.title
      // Drafts only appear here when the setting is on, and the reason to turn
      // it on is knowing which requests are early feedback rather than a real
      // review, so the row has to say which it is.
      detail: modelData.repository + (modelData.draft ? " · draft" : "") + " · review requested · " + root.relativeTime(modelData.updatedAt)
      url: modelData.url
    }
  }

  Component {
    id: authoredDelegate
    LinkRow {
      required property var modelData
      required property int index
      readonly property string checks: String(modelData.checks || "NONE")
      readonly property bool broken: svc.isBrokenCheck(checks)
      readonly property bool running: svc.isRunningCheck(checks)
      width: parent ? parent.width : 0
      rowKind: "authored"
      rowIndex: index
      rowId: String(modelData.id || modelData.url || index)
      // No configured pipeline/workflow reports no rollup at all, which the
      // plain item glyph conveys without implying a pending run.
      glyph: broken ? "󰅖" : (running ? "󰑮" : (checks === "SUCCESS" ? "󰄬" : root.term.itemGlyph))
      title: modelData.title
      detail: modelData.repository + root.term.refPrefix + modelData.number + (modelData.draft ? " · draft" : "") + " · " + root.checkLabel(checks) + " · " + root.relativeTime(modelData.updatedAt)
      url: modelData.url
      danger: broken
      pulse: running
    }
  }

  Component {
    id: issueDelegate
    LinkRow {
      required property var modelData
      required property int index
      width: parent ? parent.width : 0
      rowKind: "issue"
      rowIndex: index
      rowId: String(modelData.id || modelData.url || index)
      glyph: "󰅩"
      title: modelData.title
      detail: modelData.repository + " · assigned to you · " + root.relativeTime(modelData.updatedAt)
      url: modelData.url
    }
  }

  Component {
    id: runDelegate
    LinkRow {
      required property var modelData
      required property int index
      width: parent ? parent.width : 0
      rowKind: "run"
      rowIndex: index
      rowId: String(modelData.id || modelData.url || index)
      glyph: "󰑮"
      title: modelData.name
      detail: modelData.repository + " · " + modelData.status + (modelData.branch ? " · " + modelData.branch : "")
      url: modelData.url
      pulse: true
    }
  }

  Component {
    id: failedRunDelegate
    LinkRow {
      required property var modelData
      required property int index
      width: parent ? parent.width : 0
      rowKind: "failedrun"
      rowIndex: index
      rowId: String(modelData.id || modelData.url || index)
      glyph: "󰅖"
      title: modelData.name
      detail: modelData.repository + " · " + modelData.conclusion + " · " + root.relativeTime(modelData.updatedAt)
      url: modelData.url
      danger: true
    }
  }

  component DashboardSection: Column {
    id: section
    property string title: ""
    property int count: 0
    property string emptyText: ""
    property var model: []
    property Component delegateComponent: null
    property bool expanded: false
    property bool showExpansionControl: true
    property bool footerButtonsBordered: false
    property string openUrl: ""
    property int page: 0
    property int pageCount: 1
    // Optional destructive action. It arms on the first click and only runs on
    // the second, so a stray click cannot clear the section.
    property string actionText: ""
    property string actionConfirmText: "Confirm?"
    property string actionBusyText: ""
    property bool actionEnabled: false
    property bool actionBusy: false
    property bool actionArmed: false
    property int actionRevision: 0
    property var actionPrepare: null
    property string preparedAction: ""
    signal toggleExpanded()
    signal previousPage()
    signal nextPage()
    signal actionTriggered(string prepared)

    function disarmAction() {
      section.actionArmed = false
      section.preparedAction = ""
      actionArmTimer.stop()
    }

    // An armed confirmation must not outlive the button being clickable, or it
    // would fire on the first click once the button comes back.
    onActionBusyChanged: if (section.actionBusy) section.disarmAction()
    onActionEnabledChanged: if (!section.actionEnabled) section.disarmAction()
    onActionRevisionChanged: if (section.actionArmed) section.disarmAction()

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    PanelSeparator { foreground: root.foreground }
    PanelSectionHeader {
      width: parent.width
      text: section.title + "  " + section.count
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Text {
      visible: section.count === 0
      width: parent.width
      text: section.emptyText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
    }
    Column {
      width: parent.width
      spacing: Style.space(4)
      Repeater { model: section.model; delegate: section.delegateComponent }
    }
    Timer {
      id: actionArmTimer
      interval: 4000
      repeat: false
      onTriggered: section.actionArmed = false
    }
    Row {
      id: sectionFooter
      // Expanding is only offered once the section is truncated; below that
      // threshold the remaining controls render unbordered on their own line.
      readonly property bool expandable: section.showExpansionControl && section.count > root.activityPreviewCount
      readonly property bool paginated: section.pageCount > 1
      readonly property bool showOpen: section.count > 0 && section.openUrl !== ""
      readonly property bool showAction: section.count > 0 && section.actionText !== ""
      visible: expandable || paginated || showOpen || showAction
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(12)
      Button {
        visible: sectionFooter.expandable
        text: section.expanded ? "Show less" : (section.count > root.activityExpandedCount ? "Show 25" : "Show all " + section.count)
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: section.toggleExpanded()
      }
      Button {
        id: actionButton
        // The confirm and busy labels are shorter than the idle one. Letting the
        // button shrink would slide its neighbours under a pointer that is about
        // to click again, so the widest label seen so far sets the width.
        property real reservedWidth: 0
        onImplicitWidthChanged: reservedWidth = Math.max(reservedWidth, implicitWidth)
        width: Math.max(reservedWidth, implicitWidth)
        visible: sectionFooter.showAction
        enabled: section.actionEnabled && !section.actionBusy
        text: section.actionBusy ? section.actionBusyText : (section.actionArmed ? section.actionConfirmText : section.actionText)
        bordered: sectionFooter.expandable || section.footerButtonsBordered
        foreground: section.actionArmed ? root.urgent : root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: {
          if (section.actionBusy) return
          if (!section.actionArmed) {
            var prepared = section.actionPrepare ? String(section.actionPrepare() || "") : "confirmed"
            if (prepared === "") return
            section.preparedAction = prepared
            section.actionArmed = true
            actionArmTimer.restart()
            return
          }
          var confirmed = section.preparedAction
          section.disarmAction()
          section.actionTriggered(confirmed)
        }
      }
      Button {
        id: previousPageButton
        visible: sectionFooter.paginated
        text: "󰅁"
        tooltipText: "Previous notifications"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        verticalPadding: Style.spacing.controlPaddingY
        enabled: section.page > 0
        onClicked: section.previousPage()
      }
      Text {
        visible: sectionFooter.paginated
        text: (section.page + 1) + " / " + section.pageCount
        height: previousPageButton.height
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        verticalAlignment: Text.AlignVCenter
      }
      Button {
        visible: sectionFooter.paginated
        text: "󰅂"
        tooltipText: "Next notifications"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        verticalPadding: Style.spacing.controlPaddingY
        enabled: section.page + 1 < section.pageCount
        onClicked: section.nextPage()
      }
      Button {
        visible: sectionFooter.showOpen
        text: root.term.openInLabel
        bordered: sectionFooter.expandable || section.footerButtonsBordered
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: root.openUrl(section.openUrl)
      }
    }
  }

  component LinkRow: CursorSurface {
    id: linkRow
    property string glyph: ""
    property string title: ""
    property string detail: ""
    property string url: ""
    property bool pulse: false
    property bool danger: false
    property bool showReadAction: false
    property bool showTrailingIndicator: true
    property string notificationId: ""
    property string rowKind: ""
    property int rowIndex: 0
    property string rowId: ""
    readonly property string cursorKey: rowKind + ":" + rowId
    hasCursor: root.cursorActive && root.selectedKey() === cursorKey
    onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(linkRow)
    foreground: root.foreground
    implicitHeight: row.implicitHeight + Style.space(16)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.selectKey(linkRow.cursorKey)
      onClicked: root.openRow(linkRow.rowKind, linkRow.notificationId || linkRow.rowId, linkRow.url)
    }
    RowLayout {
      id: row
      anchors.left: parent.left
      anchors.right: readActionStrip.visible ? readActionStrip.left : parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(9)
      anchors.rightMargin: readActionStrip.visible ? 0 : Style.space(9)
      spacing: Style.space(9)
      Text {
        text: linkRow.glyph
        color: linkRow.pulse || linkRow.danger ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
        SequentialAnimation on opacity {
          running: linkRow.pulse
          NumberAnimation { to: 0.35; duration: 650 }
          NumberAnimation { to: 1; duration: 650 }
          loops: Animation.Infinite
        }
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          text: linkRow.title
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: linkRow.detail
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
      Text {
        visible: linkRow.showTrailingIndicator
        text: "󰅂"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
    BorderSurface {
      id: readActionStrip
      visible: linkRow.showReadAction
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Style.space(32)
      radius: 0
      color: "transparent"
      borderSpec: Border.none()

      HoverHandler {
        onHoveredChanged: if (hovered) root.selectKey(linkRow.cursorKey)
      }

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.normalBorderWidth
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
      }

      PanelActionButton {
        id: readAction
        anchors.fill: parent
        enabled: svc.markingNotificationId !== linkRow.notificationId
        iconText: svc.markingNotificationId === linkRow.notificationId ? "󰑐" : "󰄬"
        tooltipText: "Mark this notification read (M)"
        foreground: root.foreground
        hoverColor: Color.accent
        fontFamily: root.fontFamily
        bordered: false
        onClicked: svc.markNotificationRead(linkRow.notificationId)
      }
    }
  }

  component RepositoryRow: CursorSurface {
    id: repoRow
    property var repo: null
    property int rowIndex: 0
    readonly property string cursorKey: root.targetKey("repo", repo, rowIndex)
    hasCursor: root.cursorActive && root.selectedKey() === cursorKey
    onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(repoRow)
    foreground: root.foreground
    implicitHeight: repoLayout.implicitHeight + Style.space(16)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.selectKey(repoRow.cursorKey)
      onClicked: if (repoRow.repo) root.openUrl(repoRow.repo.url)
    }
    RowLayout {
      id: repoLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(9)
      anchors.rightMargin: Style.space(9)
      spacing: Style.space(8)
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)
        Text {
          Layout.fillWidth: true
          text: repoRow.repo ? repoRow.repo.nameWithOwner : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: {
            if (!repoRow.repo) return ""
            var parts = ["Issues " + Number(repoRow.repo.issues || 0),
                         root.term.itemFilterLabel + " " + Number(repoRow.repo.prs || 0),
                         "Stars " + Number(repoRow.repo.stars || 0)]
            if (Number(repoRow.repo.activeRuns || 0) > 0)
              parts.push(root.term.activeMetricLabel + " " + Number(repoRow.repo.activeRuns))
            parts.push("updated " + root.relativeTime(repoRow.repo.updatedAt))
            return parts.join("  ·  ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

}
