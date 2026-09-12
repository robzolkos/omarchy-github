import QtQuick
import QtTest
import "../.."

TestCase {
  name: "GitHubUrlLauncher"

  property var launcher: null
  property var browserCalls: []
  property var webAppCalls: []

  Component {
    id: launcherComponent
    UrlLauncher {}
  }

  function init() {
    browserCalls = []
    webAppCalls = []
    launcher = launcherComponent.createObject(this)
    verify(launcher !== null)
    launcher.browserLaunchRequested.connect(function(argv) {
      browserCalls = browserCalls.concat([argv])
    })
    launcher.webAppLaunchRequested.connect(function(argv) {
      webAppCalls = webAppCalls.concat([argv])
    })
  }

  function cleanup() {
    launcher.destroy()
    launcher = null
  }

  function test_canonical_github_urls_launch_with_configured_handler_data() {
    return [
      { tag: "browser-origin", behavior: "Browser tab", url: "https://github.com", browserCount: 1, webAppCount: 0 },
      { tag: "browser-path", behavior: "Browser tab", url: "https://github.com/octocat/Hello-World?tab=readme#readme", browserCount: 1, webAppCount: 0 },
      { tag: "webapp-origin", behavior: "Web app window", url: "https://github.com/", browserCount: 0, webAppCount: 1 },
      { tag: "webapp-path", behavior: "Web app window", url: "https://github.com/notifications", browserCount: 0, webAppCount: 1 }
    ]
  }

  function test_canonical_github_urls_launch_with_configured_handler(data) {
    launcher.linkBehavior = data.behavior

    verify(launcher.openUrl(data.url))
    compare(browserCalls.length, data.browserCount)
    compare(webAppCalls.length, data.webAppCount)

    var call = data.browserCount === 1 ? browserCalls[0] : webAppCalls[0]
    compare(call.length, 2)
    compare(call[0], data.browserCount === 1 ? "xdg-open" : "omarchy-launch-webapp")
    compare(call[1], data.url)
  }

  function test_non_github_origins_never_launch_data() {
    return [
      { tag: "empty", url: "" },
      { tag: "file", url: "file:///etc/passwd" },
      { tag: "javascript", url: "javascript:alert(1)" },
      { tag: "custom-scheme", url: "steam://run/10" },
      { tag: "protocol-relative", url: "//github.com/octocat" },
      { tag: "userinfo", url: "https://github.com@evil.example/octocat" },
      { tag: "port", url: "https://github.com:443/octocat" },
      { tag: "subdomain-lookalike", url: "https://github.com.evil.example/octocat" },
      { tag: "suffix-lookalike", url: "https://notgithub.com/octocat" },
      { tag: "prefix-lookalike", url: "https://github.comexample.org/octocat" },
      { tag: "case-normalization", url: "HTTPS://GITHUB.COM/octocat" },
      { tag: "leading-whitespace", url: " https://github.com/octocat" },
      { tag: "trailing-newline", url: "https://github.com\n" },
      { tag: "authority-backslash", url: "https://github.com\\@evil.example/octocat" }
    ]
  }

  function test_non_github_origins_never_launch(data) {
    var behaviors = ["Browser tab", "Web app window"]
    for (var i = 0; i < behaviors.length; i++) {
      launcher.linkBehavior = behaviors[i]
      verify(!launcher.openUrl(data.url))
    }

    compare(browserCalls.length, 0)
    compare(webAppCalls.length, 0)
  }
}
