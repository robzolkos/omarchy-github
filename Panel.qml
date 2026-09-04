import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "pranavbabu.gitlab"
  ipcTarget: "pranavbabu.gitlab"
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
  property bool myMergeRequestsExpanded: false
  property bool issuesExpanded: false
  property bool pipelinesExpanded: false
  property bool failuresExpanded: false
  // settingsOpen is the page on screen; pendingSettingsOpen is the page the
  // in-flight flip will land on, since the swap happens edge-on at 90 degrees.
  property bool settingsOpen: false
  property bool pendingSettingsOpen: false
  readonly property var linkBehaviorOptions: [
    { value: "Web app window", label: "Web app window" },
    { value: "Browser tab", label: "Browser tab" }
  ]
  readonly property var projectScopeOptions: [
    { value: "Owned", label: "Owned projects" },
    { value: "Member of", label: "Member of" }
  ]
  readonly property var refreshIntervalOptions: [
    { value: "300", label: "Every 5 minutes" },
    { value: "600", label: "Every 10 minutes" },
    { value: "900", label: "Every 15 minutes" },
    { value: "1800", label: "Every 30 minutes" },
    { value: "3600", label: "Every hour" }
  ]
  // Carry sub-notch wheel deltas between events. Touchpads emit many small
  // angleDeltas; mice often emit a fake 1–2px pixelDelta that would otherwise
  // crawl the dashboard a couple of pixels per click.
  property real wheelAccumulator: 0
  readonly property int activityPreviewCount: 5
  readonly property int activityExpandedCount: 25
  readonly property var metricFilters: [
    { id: "all", label: "All" }, { id: "issues", label: "Issues" },
    { id: "prs", label: "MRs" }, { id: "stars", label: "Stars" },
    { id: "pipelines", label: "Pipelines" }
  ]
  readonly property var sortModes: [
    { value: "updated", label: "Updated" }, { value: "name", label: "Name" },
    { value: "stars", label: "Stars" }, { value: "issues", label: "Issues" },
    { value: "prs", label: "MRs" }, { value: "pipelines", label: "Pipelines" }
  ]
  readonly property var displayedProjects: filteredProjects()
  readonly property var cursorTargets: buildCursorTargets()
  readonly property var selectedTarget: cursorTargets.length > 0 ? cursorTargets[Math.max(0, Math.min(cursorIndex, cursorTargets.length - 1))] : null

  function sectionRows(rows, expanded) {
    return rows.slice(0, expanded ? activityExpandedCount : activityPreviewCount)
  }

  function notificationPageCount() {
    return Math.max(1, Math.ceil(gitlab.notifications.length / activityPreviewCount))
  }

  function notificationRows() {
    var page = Math.max(0, Math.min(notificationsPage, notificationPageCount() - 1))
    if (page !== notificationsPage) notificationsPage = page
    var start = page * activityPreviewCount
    return gitlab.notifications.slice(start, start + activityPreviewCount)
  }

  function buildCursorTargets() {
    var targets = []
    function add(kind, rows) {
      for (var i = 0; i < rows.length; i++) targets.push({ key: kind + ":" + String(rows[i].id || rows[i].url || i), kind: kind, row: rows[i] })
    }
    add("notification", notificationRows())
    add("review", sectionRows(gitlab.reviewRequests, reviewsExpanded))
    add("mymr", sectionRows(gitlab.myMergeRequests, myMergeRequestsExpanded))
    add("issue", sectionRows(gitlab.assignedIssues, issuesExpanded))
    add("pipeline", sectionRows(gitlab.pipelines, pipelinesExpanded))
    add("failedpipeline", sectionRows(gitlab.failedPipelines, failuresExpanded))
    add("project", displayedProjects)
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
    if (kind === "notification") gitlab.markNotificationRead(notificationId)
  }
  function markSelectedRead() {
    if (selectedTarget && selectedTarget.kind === "notification") gitlab.markNotificationRead(String(selectedTarget.row.id || ""))
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
    if (gitlab.isBrokenCheck(checks)) return "checks failing"
    if (gitlab.isRunningCheck(checks)) return "checks running"
    return "no checks"
  }

  function openUrl(url) {
    var value = String(url || "")
    if (value === "") return
    // omarchy-launch-webapp gives GitLab its own window; omarchy-launch-browser
    // hands the URL to the default browser for those without a Chromium-based one.
    if (gitlab.linkBehavior === "Browser tab") Quickshell.execDetached(["omarchy-launch-browser", value])
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
    linkBehaviorDropdown.close()
    projectScopeDropdown.close()
    refreshIntervalDropdown.close()
    if (sortPicker) sortPicker.close()
    pageFlip.restart()
  }

  function filteredProjects() {
    var needle = String(query || "").trim().toLowerCase()
    var rows = []
    for (var i = 0; i < gitlab.projects.length; i++) {
      var project = gitlab.projects[i]
      if (needle !== "" && String(project.nameWithOwner || project.name || "").toLowerCase().indexOf(needle) === -1) continue
      if (metricFilter === "issues" && Number(project.issues || 0) <= 0) continue
      if (metricFilter === "prs" && Number(project.prs || 0) <= 0) continue
      if (metricFilter === "stars" && Number(project.stars || 0) <= 0) continue
      if (metricFilter === "pipelines" && Number(project.activePipelines || 0) <= 0) continue
      rows.push(project)
    }
    rows.sort(function(a, b) {
      if (sortMode === "name") return String(a.nameWithOwner).localeCompare(String(b.nameWithOwner))
      if (sortMode === "updated") return String(b.updatedAt).localeCompare(String(a.updatedAt))
      var av = Number(a[sortMode] || (sortMode === "pipelines" ? a.activePipelines : 0) || 0)
      var bv = Number(b[sortMode] || (sortMode === "pipelines" ? b.activePipelines : 0) || 0)
      if (av !== bv) return bv - av
      return String(a.nameWithOwner).localeCompare(String(b.nameWithOwner))
    })
    return rows.slice(0, Math.max(10, Number(setting("maxDisplayedProjects", 25))))
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
      gitlab.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }
  onCursorTargetsChanged: ensureCursor()

  Service { id: gitlab; settings: root.settings }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { gitlab.refresh(); return "ok" }
    function status(): string { return gitlab.state }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰮠"
    active: gitlab.alarming
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) gitlab.refresh()
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
        if (text === "r" || text === "R") gitlab.refresh()
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
            if (root.settingsOpen) linkBehaviorDropdown.forceActiveFocus()
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
            title: gitlab.login !== "" ? "GitLab · " + gitlab.login : "GitLab"
            // Mirrors every term of the alarming state, so the summary always
            // explains why the bar icon is lit.
            meta: gitlab.loading ? "Refreshing dashboard…" : (gitlab.state === "ready" ?
              gitlab.unreadCount + " unread · " + gitlab.reviewRequests.length + " reviews · " + gitlab.pipelineCount + " active pipelines"
                + (gitlab.failingMergeRequestCount > 0 ? " · " + gitlab.failingMergeRequestCount + " failing" : "") : gitlab.message)
            foreground: root.foreground
            fontFamily: root.fontFamily
            // The hero reserves the trailing space and centres the control
            // against the labels, so the gear needs no geometry of its own.
            trailingControl: Component {
              PanelActionButton {
                iconText: "󰒓"
                tooltipText: "GitLab settings"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.showSettings(true)
              }
            }
            iconComponent: Component {
              Text {
                text: "󰮠"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }
            }
          }

          Text {
            visible: gitlab.notificationActionStatus !== ""
            width: parent.width
            text: gitlab.notificationActionStatus
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          BorderSurface {
            visible: gitlab.state !== "ready" || gitlab.warnings.length > 0
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
                if (gitlab.state !== "ready") return gitlab.message
                var summary = "Partial results · " + String(gitlab.warnings[0] || "A GitLab request failed.")
                if (gitlab.warnings.length > 1) summary += " · " + (gitlab.warnings.length - 1) + " more"
                return summary
              }
              textFormat: Text.PlainText
              color: gitlab.state === "ready" ? root.dim : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          DashboardSection {
            id: notificationsSection
            title: "UNREAD NOTIFICATIONS"
            count: gitlab.notifications.length
            emptyText: gitlab.state === "ready" ? "You're all caught up." : "No notifications loaded."
            model: root.notificationRows()
            showExpansionControl: false
            footerButtonsBordered: true
            page: root.notificationsPage
            pageCount: root.notificationPageCount()
            openUrl: gitlab.host + "/dashboard/todos"
            onPreviousPage: root.notificationsPage = Math.max(0, root.notificationsPage - 1)
            onNextPage: root.notificationsPage = Math.min(root.notificationPageCount() - 1, root.notificationsPage + 1)
            delegateComponent: notificationDelegate
            actionText: "Mark all read"
            actionBusyText: "Marking…"
            actionEnabled: gitlab.state === "ready" && !gitlab.loading
            actionBusy: gitlab.marking
            actionRevision: gitlab.notificationsRevision
            actionPrepare: function() { return gitlab.prepareMarkAllNotificationsRead() }
            onActionTriggered: function(prepared) { gitlab.markAllNotificationsRead(prepared) }
          }

          DashboardSection {
            visible: count > 0
            title: "REVIEW REQUESTS"
            count: gitlab.reviewRequests.length
            model: root.sectionRows(gitlab.reviewRequests, root.reviewsExpanded)
            expanded: root.reviewsExpanded
            openUrl: gitlab.host + "/dashboard/merge_requests?reviewer_username=" + gitlab.login
            onToggleExpanded: root.reviewsExpanded = !root.reviewsExpanded
            delegateComponent: reviewDelegate
          }

          DashboardSection {
            visible: count > 0
            title: "MY MERGE REQUESTS"
            // The query is capped at one page, so the fetched list can be
            // shorter than the real total. Show the total rather than implying
            // the section is complete.
            count: Math.max(gitlab.myMergeRequestsTotal, gitlab.myMergeRequests.length)
            model: root.sectionRows(gitlab.myMergeRequests, root.myMergeRequestsExpanded)
            expanded: root.myMergeRequestsExpanded
            openUrl: gitlab.host + "/dashboard/merge_requests?author_username=" + gitlab.login
            onToggleExpanded: root.myMergeRequestsExpanded = !root.myMergeRequestsExpanded
            delegateComponent: myMergeRequestDelegate
          }

          DashboardSection {
            visible: count > 0
            title: "ASSIGNED ISSUES"
            count: gitlab.assignedIssues.length
            model: root.sectionRows(gitlab.assignedIssues, root.issuesExpanded)
            expanded: root.issuesExpanded
            footerButtonsBordered: true
            openUrl: gitlab.host + "/dashboard/issues?assignee_username=" + gitlab.login
            onToggleExpanded: root.issuesExpanded = !root.issuesExpanded
            delegateComponent: issueDelegate
          }

          DashboardSection {
            visible: count > 0
            title: "RUNNING PIPELINES"
            count: gitlab.pipelines.length
            model: root.sectionRows(gitlab.pipelines, root.pipelinesExpanded)
            expanded: root.pipelinesExpanded
            onToggleExpanded: root.pipelinesExpanded = !root.pipelinesExpanded
            delegateComponent: pipelineDelegate
          }

          DashboardSection {
            visible: count > 0
            title: "RECENT FAILED PIPELINES"
            count: gitlab.failedPipelines.length
            model: root.sectionRows(gitlab.failedPipelines, root.failuresExpanded)
            expanded: root.failuresExpanded
            onToggleExpanded: root.failuresExpanded = !root.failuresExpanded
            delegateComponent: failedPipelineDelegate
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            width: parent.width
            // Driven by the fetched scope, not the setting, so it cannot claim
            // to list every membership project before a refresh brings them in.
            text: (gitlab.fetchedProjectScope === "owned" ? "OWNED PROJECTS  " : "PROJECTS  ") + root.displayedProjects.length + "/" + gitlab.projects.length
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          TextField {
            id: search
            width: parent.width
            foreground: root.foreground
            placeholderText: "Filter projects  /"
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
            visible: root.displayedProjects.length === 0
            width: parent.width
            text: gitlab.projects.length === 0 ? "No projects loaded." : "No projects match these filters."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: root.displayedProjects
              ProjectRow {
                required property var modelData
                required property int index
                width: parent.width
                project: modelData
                rowIndex: index
              }
            }
          }

          Text {
            visible: gitlab.rateLimit && gitlab.rateLimit.remaining !== undefined
            width: parent.width
            text: "API requests remaining: " + (gitlab.rateLimit ? gitlab.rateLimit.remaining : "") +
              (gitlab.fetchedAt !== "" ? " · updated " + root.relativeTime(gitlab.fetchedAt) : "")
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
                text: "GITLAB SETTINGS"
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
                Binding on value { value: gitlab.linkBehavior }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "PROJECT SCOPE"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Dropdown {
                id: projectScopeDropdown
                width: parent.width
                showLabel: false
                options: root.projectScopeOptions
                foreground: root.foreground
                background: Color.popups.background
                accent: Color.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { root.persistSettings({ projectScope: value }) }

                Binding on value { value: String(root.setting("projectScope", "Owned")) }
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
              description: "Leave the icon dim even when notifications, reviews, or failing pipelines are waiting."
              checked: gitlab.iconAlwaysUnlit
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ iconAlwaysUnlit: !gitlab.iconAlwaysUnlit })
            }

            Toggle {
              width: parent.width
              label: "Include archived projects"
              description: "Show projects that have been archived on GitLab."
              checked: root.setting("includeArchived", false) === true
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ includeArchived: !(root.setting("includeArchived", false) === true) })
            }

            Toggle {
              width: parent.width
              label: "Include forked projects"
              description: "Show projects you forked from someone else."
              checked: root.setting("includeForks", false) === true
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSettings({ includeForks: !(root.setting("includeForks", false) === true) })
            }

            Text {
              width: parent.width
              text: "The remaining options — pipeline scanning, review request filters, and display limits — stay in Omarchy's bar widget settings."
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
      glyph: modelData.type === "MergeRequest" ? "󰘭" : "󰍩"
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
      glyph: "󰘭"
      title: modelData.title
      // Drafts only appear here when the setting is on, and the reason to turn
      // it on is knowing which requests are early feedback rather than a real
      // review, so the row has to say which it is.
      detail: modelData.repository + (modelData.draft ? " · draft" : "") + " · review requested · " + root.relativeTime(modelData.updatedAt)
      url: modelData.url
    }
  }

  Component {
    id: myMergeRequestDelegate
    LinkRow {
      required property var modelData
      required property int index
      readonly property string checks: String(modelData.checks || "NONE")
      readonly property bool broken: gitlab.isBrokenCheck(checks)
      readonly property bool running: gitlab.isRunningCheck(checks)
      width: parent ? parent.width : 0
      rowKind: "mymr"
      rowIndex: index
      rowId: String(modelData.id || modelData.url || index)
      // A merge request with no configured pipeline reports no rollup at all,
      // which the plain merge request glyph conveys without implying a
      // pending run.
      glyph: broken ? "󰅖" : (running ? "󰑮" : (checks === "SUCCESS" ? "󰄬" : "󰘭"))
      title: modelData.title
      detail: modelData.repository + " !" + modelData.number + (modelData.draft ? " · draft" : "") + " · " + root.checkLabel(checks) + " · " + root.relativeTime(modelData.updatedAt)
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
    id: pipelineDelegate
    LinkRow {
      required property var modelData
      required property int index
      width: parent ? parent.width : 0
      rowKind: "pipeline"
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
    id: failedPipelineDelegate
    LinkRow {
      required property var modelData
      required property int index
      width: parent ? parent.width : 0
      rowKind: "failedpipeline"
      rowIndex: index
      rowId: String(modelData.id || modelData.url || index)
      glyph: "󰅖"
      title: modelData.name
      detail: modelData.repository + " · " + modelData.status + " · " + root.relativeTime(modelData.updatedAt)
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
        text: "Open in GitLab  󰅂"
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
        enabled: gitlab.markingNotificationId !== linkRow.notificationId
        iconText: gitlab.markingNotificationId === linkRow.notificationId ? "󰑐" : "󰄬"
        tooltipText: "Mark this notification read (M)"
        foreground: root.foreground
        hoverColor: Color.accent
        fontFamily: root.fontFamily
        bordered: false
        onClicked: gitlab.markNotificationRead(linkRow.notificationId)
      }
    }
  }

  component ProjectRow: CursorSurface {
    id: projectRow
    property var project: null
    property int rowIndex: 0
    readonly property string cursorKey: root.targetKey("project", project, rowIndex)
    hasCursor: root.cursorActive && root.selectedKey() === cursorKey
    onHasCursorChanged: if (hasCursor) root.scrollItemIntoView(projectRow)
    foreground: root.foreground
    implicitHeight: projectLayout.implicitHeight + Style.space(16)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.selectKey(projectRow.cursorKey)
      onClicked: if (projectRow.project) root.openUrl(projectRow.project.url)
    }
    RowLayout {
      id: projectLayout
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
          text: projectRow.project ? projectRow.project.nameWithOwner : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: {
            if (!projectRow.project) return ""
            var parts = ["Issues " + Number(projectRow.project.issues || 0),
                         "MRs " + Number(projectRow.project.prs || 0),
                         "Stars " + Number(projectRow.project.stars || 0)]
            if (Number(projectRow.project.activePipelines || 0) > 0)
              parts.push("Pipelines " + Number(projectRow.project.activePipelines))
            parts.push("updated " + root.relativeTime(projectRow.project.updatedAt))
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
