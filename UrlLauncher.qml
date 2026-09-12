import QtQml

QtObject {
  property string linkBehavior: "Web app window"

  signal browserLaunchRequested(var argv)
  signal webAppLaunchRequested(var argv)

  function isAllowedUrl(url) {
    var value = String(url || "")
    // Links in this plugin are GitHub destinations. Keep the authority exact:
    // accepting arbitrary HTTPS URLs would let API data select another host.
    return /^https:\/\/github[.]com(?:[\/?#]|$)/.test(value)
  }

  function openUrl(url) {
    var value = String(url || "")
    if (!isAllowedUrl(value)) return false

    if (linkBehavior === "Browser tab")
      browserLaunchRequested(["xdg-open", value])
    else
      webAppLaunchRequested(["omarchy-launch-webapp", value])
    return true
  }
}
