import QtQuick
import QtTest
import Quickshell as Qs
import Quickshell.Io as QsIo
import qs.Commons as Commons
import "../.."

TestCase {
  name: "PanelNotificationActivation"

  property var panel: null

  Component {
    id: panelComponent
    Panel {}
  }

  function markCalls() {
    var calls = []
    for (var i = 0; i < QsIo.ProcessRegistry.processes.length; i++) {
      var command = QsIo.ProcessRegistry.processes[i].command
      if (command.indexOf("--mark-notification-read") !== -1) calls.push(command)
    }
    return calls
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

  function test_notification_activation_obeys_url_policy_data() {
    return [
      { tag: "browser", behavior: "Browser tab", browserCount: 1, webAppCount: 0 },
      { tag: "web-app", behavior: "Web app window", browserCount: 0, webAppCount: 1 }
    ]
  }

  function test_notification_activation_obeys_url_policy(data) {
    panel = panelComponent.createObject(this, { settings: { linkBehavior: data.behavior } })
    verify(panel !== null)

    panel.openRow("notification", "123", "https://github.com@evil.example/octocat")
    compare(Commons.Util.execCalls.length, 0)
    compare(Qs.Quickshell.execCalls.length, 0)
    compare(markCalls().length, 0)
    compare(panel.closeCalls, 0)

    panel.openRow("notification", "123", "https://github.com/octocat/hello/issues/1")
    compare(Commons.Util.execCalls.length, data.browserCount)
    compare(Qs.Quickshell.execCalls.length, data.webAppCount)
    compare(markCalls().length, 1)
    compare(panel.closeCalls, 1)
  }
}
