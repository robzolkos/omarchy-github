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

  function payload(state, message, notifications, contributions, preserveDashboard) {
    return JSON.stringify({
      state: state,
      message: message,
      preserveDashboard: preserveDashboard === true,
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

  function accountNotification(id, account, updatedAt) {
    var item = notification(id, updatedAt)
    item.account = account
    return item
  }

  // What the helper emits when gh holds several logins: rows tagged with the
  // account they came from, no single login, and a summary per account.
  function multiAccountPayload(notifications) {
    var data = JSON.parse(payload("ready", "Ready", notifications))
    data.login = ""
    data.accounts = [
      {login: "alice", state: "ready", message: "", contributions: {total: 0, days: []}},
      {login: "bob", state: "ready", message: "", contributions: {total: 0, days: []}}
    ]
    return JSON.stringify(data)
  }

  function completeMultiAccountReady(notifications) {
    fetchProcess().complete(0, multiAccountPayload(notifications), "")
    compare(service.state, "ready")
  }

  function markOneProcess() {
    for (var i = 0; i < QsIo.ProcessRegistry.processes.length; i++) {
      var process = QsIo.ProcessRegistry.processes[i]
      if (process.command.indexOf("--mark-notification-read") !== -1) return process
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
    service.initialize({})
    tryVerify(function() { return fetchProcess() !== null && fetchProcess().running })
  }

  function cleanup() {
    service.destroy()
    service = null
    wait(0)
  }

  function test_initialization_waits_for_injected_settings() {
    service.destroy()
    service = serviceComponent.createObject(this)
    verify(service !== null)
    wait(0)
    compare(fetchProcess(), null)

    service.initialize({includeContributions: false})
    tryVerify(function() { return fetchProcess() !== null && fetchProcess().running })
    var command = fetchProcess().command
    var option = command.indexOf("--include-contributions")
    verify(option >= 0)
    compare(command[option + 1], "false")
    verify(command.indexOf("--automatic") >= 0)
  }

  function test_queued_automatic_refresh_stays_cache_aware() {
    service.automaticRefresh()
    compare(service.refreshQueued, true)
    compare(service.refreshQueuedAutomatic, true)
    fetchProcess().complete(0, payload("ready", "Ready", []), "")
    tryVerify(function() { return fetchProcess().running })
    verify(fetchProcess().command.indexOf("--automatic") >= 0)
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

  function test_bulk_mark_waits_for_fetch_and_requires_fresh_confirmation() {
    completeInitialReady([notification("101")])
    var preparedAtT0 = service.prepareMarkAllNotificationsRead()
    verify(preparedAtT0 !== "")

    service.refresh()
    verify(fetchProcess().running)
    compare(service.prepareMarkAllNotificationsRead(), "")

    service.markAllNotificationsRead(preparedAtT0)
    compare(markProcess(), null)
    compare(service.unreadCount, 1)

    fetchProcess().complete(0, payload("ready", "Ready", [
      notification("101", "2020-01-02T00:00:00Z")
    ]), "")
    service.markAllNotificationsRead(preparedAtT0)
    compare(markProcess(), null)
    compare(service.notificationActionStatus, "Notifications changed. Confirm again.")
    compare(service.unreadCount, 1)

    var preparedAtT1 = service.prepareMarkAllNotificationsRead()
    verify(preparedAtT1 !== "")
    verify(preparedAtT1 !== preparedAtT0)
    service.markAllNotificationsRead(preparedAtT1)

    var marking = markProcess()
    verify(marking !== null)
    verify(marking.running)
    compare(marking.command, [
      service.helperPath(),
      "--mark-all-read-before", "2020-01-02T00:00:00Z",
      "--mark-boundary-notification", "101"
    ])
  }

  function test_successful_bulk_mark_reconciles_hidden_rows() {
    completeInitialReady([notification("101")])
    var prepared = service.prepareMarkAllNotificationsRead()
    service.markAllNotificationsRead(prepared)

    compare(service.notifications.length, 0)
    verify(service.hiddenNotifications["101"] !== undefined)
    markProcess().complete(0, '{"state":"ready"}', "")

    tryVerify(function() { return fetchProcess().running })
    fetchProcess().complete(0, payload("ready", "Ready", [notification("202", "2020-01-02T00:00:00Z")]), "")
    compare(service.notifications.length, 1)
    compare(service.notifications[0].id, "202")
    compare(Object.keys(service.hiddenNotifications).length, 0)
  }

  function test_failed_bulk_mark_restores_rows_then_refreshes() {
    completeInitialReady([notification("101")])
    var prepared = service.prepareMarkAllNotificationsRead()
    service.markAllNotificationsRead(prepared)

    compare(service.notifications.length, 0)
    markProcess().complete(1, '{"state":"error","message":"Permission denied"}', "")
    compare(service.notifications.length, 1)
    compare(service.notifications[0].id, "101")
    compare(service.notificationActionStatus, "Permission denied")

    tryVerify(function() { return fetchProcess().running })
    fetchProcess().complete(0, payload("ready", "Ready", [
      {id: "101", updatedAt: "2020-01-01T00:00:00Z", title: "Fresh title"},
      notification("202", "2020-01-02T00:00:00Z")
    ]), "")
    compare(service.notifications.length, 2)
    compare(service.notifications[0].title, "Fresh title")
    compare(Object.keys(service.hiddenNotifications).length, 0)
  }

  function test_refresh_waits_for_bulk_mark() {
    completeInitialReady([notification("101")])
    var prepared = service.prepareMarkAllNotificationsRead()
    service.markAllNotificationsRead(prepared)

    service.refresh()
    compare(service.refreshQueued, true)
    verify(!fetchProcess().running)

    markProcess().complete(0, '{"state":"ready"}', "")
    tryVerify(function() { return fetchProcess().running })
    compare(service.refreshQueued, false)

    fetchProcess().complete(0, payload("ready", "Ready", []), "")
    compare(service.loading, false)
    compare(Object.keys(service.hiddenNotifications).length, 0)
  }

  function test_authoritative_refresh_can_redisplay_a_thread_updated_after_mark() {
    completeInitialReady([notification("101")])
    var prepared = service.prepareMarkAllNotificationsRead()
    service.markAllNotificationsRead(prepared)

    compare(service.notifications.length, 0)
    markProcess().complete(0, '{"state":"ready"}', "")

    tryVerify(function() { return fetchProcess().running })
    fetchProcess().complete(0, payload("ready", "Ready", [
      notification("101", "2020-01-02T00:00:00Z")
    ]), "")
    compare(service.notifications.length, 1)
    compare(service.notifications[0].id, "101")
    compare(Object.keys(service.hiddenNotifications).length, 0)
  }

  function test_fetch_revision_invalidates_prepared_bulk_mark() {
    completeInitialReady([notification("101")])
    var prepared = service.prepareMarkAllNotificationsRead()
    verify(prepared !== "")
    service.refresh()

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

  function test_rate_limit_preserves_matching_ready_dashboard() {
    completeInitialReady([notification("101")])
    service.refresh()
    fetchProcess().complete(0, payload("rate-limited", "Wait for reset", [], undefined, true), "")
    compare(service.state, "rate-limited")
    compare(service.notifications.length, 1)
    compare(service.notifications[0].id, "101")
    compare(service.repositories.length, 1)
  }

  function test_rate_limit_replaces_incompatible_ready_dashboard() {
    completeInitialReady([notification("101")])
    service.refresh()
    fetchProcess().complete(0, payload("rate-limited", "Wait for reset", []), "")
    compare(service.state, "rate-limited")
    compare(service.notifications.length, 0)
    compare(service.repositories.length, 1)
  }

  function test_accounts_are_exposed_only_for_multi_account_payloads() {
    completeInitialReady([notification("101")])
    compare(service.accounts.length, 0)

    service.refresh()
    completeMultiAccountReady([
      accountNotification("101", "alice", "2020-01-02T00:00:00Z"),
      accountNotification("201", "bob", "2020-01-05T00:00:00Z"),
      accountNotification("202", "bob", "2020-01-05T00:00:00Z")
    ])
    compare(service.accounts.length, 2)
    compare(service.accounts[0].login, "alice")
    compare(service.accounts[1].login, "bob")
    // One count for the bar icon, however the rows are spread across accounts.
    compare(service.unreadCount, 3)
    compare(service.alarming, true)

    service.refresh()
    fetchProcess().complete(0, payload("ready", "Ready", []), "")
    compare(service.accounts.length, 0)
  }

  function test_single_mark_uses_the_account_that_owns_the_thread() {
    completeMultiAccountReady([
      accountNotification("101", "alice", "2020-01-02T00:00:00Z"),
      accountNotification("201", "bob", "2020-01-05T00:00:00Z")
    ])
    service.markNotificationRead("201")
    var marking = markOneProcess()
    verify(marking !== null)
    verify(marking.running)
    compare(marking.command, [service.helperPath(), "--mark-notification-read", "201", "--account", "bob"])
  }

  function test_single_account_mark_names_no_account() {
    completeInitialReady([notification("101")])
    service.markNotificationRead("101")
    compare(markOneProcess().command, [service.helperPath(), "--mark-notification-read", "101"])
  }

  function test_queued_mark_keeps_its_account_through_a_refresh() {
    completeMultiAccountReady([accountNotification("201", "bob", "2020-01-05T00:00:00Z")])
    service.refresh()
    service.markNotificationRead("201")
    compare(markOneProcess(), null)

    // The refresh no longer lists the thread, so the row it came from is gone
    // by the time the queued mark starts.
    fetchProcess().complete(0, multiAccountPayload([]), "")
    var marking = markOneProcess()
    verify(marking !== null)
    compare(marking.command, [service.helperPath(), "--mark-notification-read", "201", "--account", "bob"])
  }

  function test_bulk_mark_runs_once_per_account_with_its_own_boundary() {
    completeMultiAccountReady([
      accountNotification("101", "alice", "2020-01-02T00:00:00Z"),
      accountNotification("201", "bob", "2020-01-05T00:00:00Z"),
      accountNotification("202", "bob", "2020-01-05T00:00:00Z"),
      accountNotification("203", "bob", "2020-01-04T00:00:00Z")
    ])
    var prepared = service.prepareMarkAllNotificationsRead()
    verify(prepared !== "")
    service.markAllNotificationsRead(prepared)
    compare(service.notifications.length, 0)

    var marking = markProcess()
    verify(marking.running)
    compare(marking.command, [
      service.helperPath(),
      "--mark-all-read-before", "2020-01-02T00:00:00Z",
      "--mark-boundary-notification", "101",
      "--account", "alice"
    ])
    marking.complete(0, '{"state":"ready"}', "")
    verify(marking.running)
    compare(marking.command, [
      service.helperPath(),
      "--mark-all-read-before", "2020-01-05T00:00:00Z",
      "--mark-boundary-notification", "201",
      "--mark-boundary-notification", "202",
      "--account", "bob"
    ])
    marking.complete(0, '{"state":"ready"}', "")
    compare(service.notificationActionStatus, "Notifications marked read. Refreshing…")

    tryVerify(function() { return fetchProcess().running })
    fetchProcess().complete(0, multiAccountPayload([]), "")
    compare(Object.keys(service.hiddenNotifications).length, 0)
  }

  function test_bulk_mark_can_be_limited_to_one_account() {
    completeMultiAccountReady([
      accountNotification("101", "alice", "2020-01-02T00:00:00Z"),
      accountNotification("201", "bob", "2020-01-05T00:00:00Z")
    ])
    var prepared = service.prepareMarkAllNotificationsRead("bob")
    verify(prepared !== "")
    service.markAllNotificationsRead(prepared)

    compare(service.notifications.length, 1)
    compare(service.notifications[0].id, "101")
    var marking = markProcess()
    compare(marking.command, [
      service.helperPath(),
      "--mark-all-read-before", "2020-01-05T00:00:00Z",
      "--mark-boundary-notification", "201",
      "--account", "bob"
    ])
    marking.complete(0, '{"state":"ready"}', "")
    compare(service.notifications.length, 1)
    compare(service.prepareMarkAllNotificationsRead("carol"), "")
  }

  function test_bulk_mark_stops_at_the_first_failing_account() {
    completeMultiAccountReady([
      accountNotification("101", "alice", "2020-01-02T00:00:00Z"),
      accountNotification("201", "bob", "2020-01-05T00:00:00Z")
    ])
    service.markAllNotificationsRead(service.prepareMarkAllNotificationsRead())

    var marking = markProcess()
    marking.complete(1, '{"state":"error","message":"Permission denied"}', "")
    // Bob is never attempted, and every row returns until GitHub confirms
    // which ones are really read.
    compare(marking.running, false)
    compare(marking.command[marking.command.length - 1], "alice")
    compare(service.notifications.length, 2)
    compare(service.notificationActionStatus, "Permission denied")
    tryVerify(function() { return fetchProcess().running })
  }

  function test_bulk_mark_failing_on_a_later_account_restores_every_row() {
    completeMultiAccountReady([
      accountNotification("101", "alice", "2020-01-02T00:00:00Z"),
      accountNotification("201", "bob", "2020-01-05T00:00:00Z")
    ])
    service.markAllNotificationsRead(service.prepareMarkAllNotificationsRead())

    var marking = markProcess()
    marking.complete(0, '{"state":"ready"}', "")
    verify(marking.running)
    marking.complete(1, '{"state":"error","message":"Bad credentials"}', "")
    compare(service.notifications.length, 2)
    compare(service.notificationActionStatus, "Bad credentials")
    tryVerify(function() { return fetchProcess().running })
    fetchProcess().complete(0, multiAccountPayload([accountNotification("201", "bob", "2020-01-05T00:00:00Z")]), "")
    compare(service.notifications.length, 1)
    compare(Object.keys(service.hiddenNotifications).length, 0)
  }
}
