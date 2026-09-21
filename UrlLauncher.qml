import QtQml

QtObject {
  property string linkBehavior: "Web app window"
  property string githubUrl: "https://github.com"

  signal browserLaunchRequested(var argv)
  signal webAppLaunchRequested(var argv)

  function isAllowedUrl(url) {
    var value = String(url || "")
    var base = String(githubUrl || "").replace(/\/+$/, "")
    if (!/^https?:\/\/[^\/?#]+(?:\/[^?#]*)?$/.test(base)) return false
    // API data may supply link targets, so constrain them to the configured
    // GitHub origin and optional installation path.
    var escaped = base.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    return new RegExp("^" + escaped + "(?:[/?#]|$)").test(value)
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
