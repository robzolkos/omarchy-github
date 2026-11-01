import QtQuick
import QtTest
import Quickshell as Qs
import Quickshell.Io as QsIo
import qs.Commons as Commons
import "../.."

TestCase {
  name: "PanelAccounts"

  property var panel: null

  Component {
    id: panelComponent
    Panel {}
  }

  function fetchProcess() {
    for (var i = 0; i < QsIo.ProcessRegistry.processes.length; i++) {
      var process = QsIo.ProcessRegistry.processes[i]
      if (process.command.indexOf("--automatic") !== -1) return process
    }
    return null
  }

  // A manual refresh drops --automatic, so match on an option every run has.
  function latestFetch() {
    for (var i = 0; i < QsIo.ProcessRegistry.processes.length; i++) {
      var process = QsIo.ProcessRegistry.processes[i]
      if (process.command.indexOf("--include-archived") !== -1) return process
    }
    return null
  }

  function days(first, second) {
    return [
      {date: "2025-09-07", count: first, level: first > 0 ? 4 : 0},
      {date: "2025-09-08", count: second, level: second > 0 ? 4 : 0}
    ]
  }

  function row(id, account, repository) {
    return {id: id, account: account, repository: repository, title: "Row " + id, url: "https://github.com/" + repository, updatedAt: "2026-01-01T00:00:00Z", number: 1, reason: "mention", type: "Issue", status: "queued", conclusion: "failure", checks: "NONE"}
  }

  // The payload the helper emits when gh holds two logins: every row tagged
  // with its account, a summary per account, and the day-by-day sum on top.
  function multiAccountPayload(extra) {
    var data = {
      state: "ready",
      message: "",
      login: "",
      repositoryScope: "owned",
      fetchedAt: "2026-01-01T00:00:00Z",
      accounts: [
        {login: "alice", state: "ready", message: "", rateLimit: {remaining: 4900}, myPullRequestsTotal: 0, contributions: {total: 4, days: days(3, 1)}},
        {login: "bob", state: "ready", message: "", rateLimit: {remaining: 4000}, myPullRequestsTotal: 60, contributions: {total: 5, days: days(1, 4)}}
      ],
      notifications: [row("201", "bob", "bob/tool"), row("101", "alice", "alice/dotfiles"), row("202", "bob", "bob/tool")],
      reviewRequests: [row("1001", "alice", "alice/dotfiles")],
      assignedIssues: [row("2001", "bob", "bob/tool")],
      myPullRequests: [row("bob/tool#3", "bob", "bob/tool")],
      myPullRequestsTotal: 60,
      actions: [row("10", "alice", "alice/dotfiles")],
      failedActions: [row("11", "bob", "bob/tool")],
      repositories: [{nameWithOwner: "alice/repo", url: "https://github.com/alice/repo", account: "alice", issues: 0, prs: 0, stars: 1, activeActions: 0, updatedAt: "2026-01-01T00:00:00Z"}, {nameWithOwner: "bob/repo", url: "https://github.com/bob/repo", account: "bob", issues: 0, prs: 0, stars: 5, activeActions: 0, updatedAt: "2026-01-02T00:00:00Z"}],
      contributions: {total: 9, days: days(4, 5)},
      warnings: [],
      rateLimit: {remaining: 4000}
    }
    for (var key in extra || {}) data[key] = extra[key]
    return JSON.stringify(data)
  }

  function open(payload) {
    panel = panelComponent.createObject(null)
    verify(panel !== null)
    panel.bar = { foreground: "#ffffff", urgent: "#ff0000", fontFamily: "sans-serif" }
    panel.settings = {}
    wait(0)
    panel.open()
    var process = fetchProcess()
    verify(process !== null)
    process.complete(0, payload, "")
  }

  function chip(id) {
    var found = findChild(panel, "accountChip-" + id)
    verify(found !== null)
    return found
  }

  function service() {
    var found = findChild(panel, "githubService")
    verify(found !== null)
    return found
  }

  function init() {
    Commons.Util.reset()
    Qs.Quickshell.reset()
  }

  function cleanup() {
    if (panel) panel.destroy()
    panel = null
    wait(0)
  }

  function test_a_single_account_shows_no_chips() {
    open('{"state":"ready","login":"octocat","notifications":[],"reviewRequests":[],"assignedIssues":[],"myPullRequests":[],"actions":[],"failedActions":[],"repositories":[],"warnings":[],"contributions":{"total":0,"days":[]}}')
    compare(findChild(panel, "accountChips").visible, false)
  }

  function test_chips_list_all_then_each_account() {
    open(multiAccountPayload())
    compare(findChild(panel, "accountChips").visible, true)
    compare(chip("all").text, "All")
    compare(chip("alice").text, "alice")
    compare(chip("bob").text, "bob")
    compare(chip("all").selected, true)
    compare(chip("bob").selected, false)
  }

  function test_all_shows_every_account_and_a_chip_filters_to_one() {
    open(multiAccountPayload())
    var notifications = findChild(panel, "notificationsSection")
    compare(notifications.count, 3)
    compare(panel.displayedRepositories.length, 2)

    chip("bob").clicked()
    compare(chip("bob").selected, true)
    compare(chip("all").selected, false)
    compare(notifications.count, 2)
    compare(notifications.model.length, 2)
    compare(notifications.model[0].id, "201")
    compare(panel.displayedRepositories.length, 1)
    compare(panel.displayedRepositories[0].nameWithOwner, "bob/repo")
    compare(panel.selectedTarget.row.id, "201")

    chip("alice").clicked()
    compare(notifications.count, 1)
    compare(notifications.model[0].id, "101")
    compare(panel.displayedRepositories[0].nameWithOwner, "alice/repo")

    chip("all").clicked()
    compare(notifications.count, 3)
    compare(panel.displayedRepositories.length, 2)
  }

  function test_the_bar_summary_keeps_counting_every_account() {
    open(multiAccountPayload())
    chip("alice").clicked()
    compare(service().unreadCount, 3)
    compare(service().alarming, true)
  }

  function test_cursor_keys_stay_distinct_for_the_same_row_on_two_accounts() {
    var shared = multiAccountPayload({
      reviewRequests: [row("77", "alice", "acme/shared"), row("77", "bob", "acme/shared")],
      notifications: []
    })
    open(shared)
    var keys = panel.cursorTargets.map(function(target) { return target.key })
    var reviews = keys.filter(function(key) { return key.indexOf("review:") === 0 })
    compare(reviews.length, 2)
    verify(reviews[0] !== reviews[1])
  }

  function test_the_calendar_sums_all_and_follows_the_chip() {
    open(multiAccountPayload())
    var calendar = findChild(panel, "contributionsBlock")
    verify(calendar !== null)
    compare(calendar.total, 9)
    compare(calendar.days[0].count, 4)

    chip("bob").clicked()
    compare(calendar.total, 5)
    compare(calendar.days[1].count, 4)
    compare(calendar.login, "bob")

    chip("alice").clicked()
    compare(calendar.total, 4)
    compare(calendar.days[0].count, 3)

    chip("all").clicked()
    compare(calendar.total, 9)
  }

  function test_authored_pull_request_total_follows_the_chip() {
    open(multiAccountPayload())
    var pulls = findChild(panel, "myPullRequestsSection")
    compare(pulls.count, 60)
    chip("alice").clicked()
    compare(pulls.count, 0)
    chip("bob").clicked()
    compare(pulls.count, 60)
  }

  function test_mark_all_is_limited_to_the_chip_and_lapses_when_it_changes() {
    open(multiAccountPayload())
    var notifications = findChild(panel, "notificationsSection")
    chip("bob").clicked()
    var scoped = JSON.parse(notifications.actionPrepare())
    compare(scoped.account, "bob")
    compare(scoped.groups.length, 1)
    compare(scoped.groups[0].account, "bob")

    notifications.preparedAction = "confirmed"
    notifications.actionArmed = true
    chip("alice").clicked()
    compare(notifications.actionArmed, false)

    chip("all").clicked()
    var everyone = JSON.parse(notifications.actionPrepare())
    compare(everyone.account, "")
    compare(everyone.groups.length, 2)
  }

  function test_a_chip_for_a_vanished_account_falls_back_to_all() {
    open(multiAccountPayload())
    chip("bob").clicked()
    compare(panel.activeAccount, "bob")
    service().refresh()
    latestFetch().complete(0, multiAccountPayload({accounts: [{login: "alice", state: "ready", message: "", contributions: {total: 4, days: days(3, 1)}}]}), "")
    compare(panel.activeAccount, "")
  }

  function test_rows_name_their_account_only_when_all_are_shown() {
    open(multiAccountPayload())
    compare(panel.accountTag(row("1", "alice", "alice/dotfiles")), "alice · ")
    chip("alice").clicked()
    compare(panel.accountTag(row("1", "alice", "alice/dotfiles")), "")
  }

  function test_the_remaining_quota_follows_the_chip() {
    open(multiAccountPayload())
    compare(panel.shownRateLimit.remaining, 4000)
    chip("alice").clicked()
    compare(panel.shownRateLimit.remaining, 4900)
  }
}
