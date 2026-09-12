import QtQuick
import QtTest
import Quickshell.Io as QsIo
import "../.."

TestCase {
  name: "ServiceRefreshOrdering"

  property var service: null

  Component {
    id: serviceComponent
    Service {}
  }

  function notification(id, updatedAt) {
    return {
      id: String(id),
      updatedAt: updatedAt || "2020-01-01T00:00:00Z",
      title: "Notification " + String(id)
    }
  }

  function payload(state, message, notifications, contributions) {
    return JSON.stringify({
      state: state,
      message: message,
      login: "octocat",
      repositoryScope: "owned",
      fetchedAt: "2020-01-01T00:00:00Z",
      notifications: notifications || [],
      reviewRequests: [{id: "review-1"}],
      assignedIssues: [],
      myPullRequests: [],
      myPullRequestsTotal: 0,
      actions: [{id: "action-1"}],
      failedActions: [],
      repositories: [{id: "repo-1"}],
      contributions: contributions || {total: 0, days: []},
      warnings: [],
      rateLimit: {remaining: state === "rate-limited" ? 0 : 42}
    })
  }

  function fetchProcess() {
    for (var i = 0; i < QsIo.ProcessRegistry.processes.length; i++) {
      var process = QsIo.ProcessRegistry.processes[i]
      if (process.command.indexOf("--include-archived") !== -1) return process
    }
    return null
  }

  function markProcess() {
    for (var i = 0; i < QsIo.ProcessRegistry.processes.length; i++) {
      var process = QsIo.ProcessRegistry.processes[i]
      if (process.command.indexOf("--mark-all-read-before") !== -1) return process
    }
    return null
  }

  function completeInitialReady(notifications) {
    var process = fetchProcess()
    verify(process !== null)
    verify(process.running)
    process.complete(0, payload("ready", "Ready", notifications), "")
    compare(service.state, "ready")
    compare(service.loading, false)
  }

  function init() {
    service = serviceComponent.createObject(this)
    verify(service !== null)
    tryVerify(function() { return fetchProcess() !== null && fetchProcess().running })
  }

  function cleanup() {
    service.destroy()
    service = null
    wait(0)
  }

  function test_first_load_and_ready_refresh_keep_snapshot() {
    compare(service.state, "loading")
    compare(service.message, "Loading GitHub…")
    compare(service.loading, true)

    var days = [{date: "2020-01-01", count: 1, level: 1}]
    fetchProcess().complete(0, payload("ready", "Ready", [notification("101")], {total: 1, days: days}), "")
    compare(service.state, "ready")
    compare(service.unreadCount, 1)
    compare(service.reviewRequests.length, 1)
    compare(service.actionCount, 1)
    compare(service.contributions.total, 1)
    compare(service.contributions.days.length, 1)

    service.refresh()
    compare(service.loading, true)
    compare(service.state, "ready")
    compare(service.unreadCount, 1)
    compare(service.contributions.days.length, 1)
  }

  function test_bulk_mark_can_prepare_and_start_during_fetch() {
    completeInitialReady([notification("101")])
    service.refresh()
    verify(fetchProcess().running)

    var prepared = service.prepareMarkAllNotificationsRead()
    verify(prepared !== "")
    service.markAllNotificationsRead(prepared)

    var marking = markProcess()
    verify(marking !== null)
    verify(marking.running)
    verify(fetchProcess().running)
    compare(service.unreadCount, 0)
    compare(marking.command, [
      service.helperPath(),
      "--mark-all-read-before", "2020-01-01T00:00:00Z",
      "--mark-boundary-notification", "101"
    ])
  }

  function test_fetch_finishing_before_mark_reconciles_hidden_rows() {
    completeInitialReady([notification("101")])
    service.refresh()
    var prepared = service.prepareMarkAllNotificationsRead()
    service.markAllNotificationsRead(prepared)

    fetchProcess().complete(0, payload("ready", "Ready", [
      notification("101"),
      notification("202", "2020-01-02T00:00:00Z")
    ]), "")
    compare(service.notifications.length, 1)
    compare(service.notifications[0].id, "202")
    verify(service.hiddenNotifications["101"] !== undefined)

    markProcess().complete(0, '{"state":"ready"}', "")
    tryVerify(function() { return fetchProcess().running })
    fetchProcess().complete(0, payload("ready", "Ready", [notification("202", "2020-01-02T00:00:00Z")]), "")
    compare(service.notifications.length, 1)
    compare(service.notifications[0].id, "202")
    compare(Object.keys(service.hiddenNotifications).length, 0)
  }

  function test_failed_mark_restores_fresh_hidden_rows_then_refreshes() {
    completeInitialReady([notification("101")])
    service.refresh()
    var prepared = service.prepareMarkAllNotificationsRead()
    service.markAllNotificationsRead(prepared)

    fetchProcess().complete(0, payload("ready", "Ready", [
      {id: "101", updatedAt: "2020-01-01T00:00:00Z", title: "Fresh title"},
      notification("202", "2020-01-02T00:00:00Z")
    ]), "")
    compare(service.notifications.length, 1)
    compare(service.notifications[0].id, "202")

    markProcess().complete(1, '{"state":"error","message":"Permission denied"}', "")
    compare(service.notifications.length, 2)
    compare(service.notifications[0].id, "101")
    compare(service.notifications[0].title, "Fresh title")
    compare(service.notifications[1].id, "202")
    compare(service.notificationActionStatus, "Permission denied")

    tryVerify(function() { return fetchProcess().running })
    fetchProcess().complete(0, payload("ready", "Ready", [
      {id: "101", updatedAt: "2020-01-01T00:00:00Z", title: "Fresh title"},
      notification("202", "2020-01-02T00:00:00Z")
    ]), "")
    compare(Object.keys(service.hiddenNotifications).length, 0)
  }

  function test_mark_finishing_before_fetch_queues_authoritative_refresh() {
    completeInitialReady([notification("101")])
    service.refresh()
    var prepared = service.prepareMarkAllNotificationsRead()
    service.markAllNotificationsRead(prepared)

    markProcess().complete(0, '{"state":"ready"}', "")
    tryCompare(service, "refreshQueued", true)
    verify(fetchProcess().running)

    fetchProcess().complete(0, payload("ready", "Ready", [
      notification("101"),
      notification("202", "2020-01-02T00:00:00Z")
    ]), "")
    tryVerify(function() { return fetchProcess().running })
    compare(service.notifications.length, 1)
    compare(service.notifications[0].id, "202")

    fetchProcess().complete(0, payload("ready", "Ready", [notification("202", "2020-01-02T00:00:00Z")]), "")
    compare(service.loading, false)
    compare(Object.keys(service.hiddenNotifications).length, 0)
  }

  function test_fetch_revision_invalidates_prepared_bulk_mark() {
    completeInitialReady([notification("101")])
    service.refresh()
    var prepared = service.prepareMarkAllNotificationsRead()
    verify(prepared !== "")

    fetchProcess().complete(0, payload("ready", "Ready", [
      notification("101"),
      notification("202", "2020-01-02T00:00:00Z")
    ]), "")
    service.markAllNotificationsRead(prepared)

    compare(markProcess(), null)
    compare(service.notificationActionStatus, "Notifications changed. Confirm again.")
    compare(service.unreadCount, 2)
  }

  function test_first_load_error_and_rate_limited_states() {
    fetchProcess().complete(1, "", "GitHub CLI unavailable")
    compare(service.loading, false)
    compare(service.state, "error")
    compare(service.message, "GitHub CLI unavailable")

    service.refresh()
    compare(service.loading, true)
    compare(service.state, "error")
    compare(service.message, "GitHub CLI unavailable")

    fetchProcess().complete(0, payload("rate-limited", "GitHub API rate limit reached.", []), "")
    compare(service.loading, false)
    compare(service.state, "rate-limited")
    compare(service.message, "GitHub API rate limit reached.")
    compare(service.rateLimit.remaining, 0)
  }
}
