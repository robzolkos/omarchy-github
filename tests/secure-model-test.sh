#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
jq -e '
  .schemaVersion == 2
  and .author == "Rob Zolkos"
  and .license == "MIT"
  and .runtime.surfaceQml == {"github":"Panel.qml","barWidget":"BarWidget.qml"}
  and .surfaces.github.role == "panel"
  and .surfaces.barWidget.role == "bar-embedded"
  and (.settings.defaults | length) == 14
  and (.settings.schema | length) == 14
  and (has("gestureActions") | not)
  and ([.permissions.required[], .permissions.optional[]] | map(.capability) | index("storage.private") | not)
  and (.permissions.required | length == 1)
  and (.permissions.required[0] | .capability == "bash.execute"
    and .definitionGeneration == 1 and .definitionDigest == "f1c859d56ceb814a21c0ab7e58087b18f4f86baeb620fdc161f9336445a272b6"
    and .operations == ["run"] and (has("profile") | not)
    and (.commands | length == 1)
    and .commands[0].command == "gh" and .commands[0].executable == "/usr/bin/gh"
    and .commands[0].accountHome == true and (.commands[0].rules | length == 11))
  and ([.permissions.optional[].capability] == ["external.open-uri.https"])
' "$root/manifest.json" >/dev/null

# Pin the entire reviewed scope, including argv, environment and limits.
scope_digest=$(jq -cS '.permissions.required' "$root/manifest.json" | sha256sum)
[[ ${scope_digest%% *} == "9f848d5250fa5f757cf3f8a98b4c491e7a9bfab5102fe5fbcc1521a3e37d79b6" ]]

! rg -n '^import (Quickshell|qs\.)|execDetached|Quickshell\.env|XDG_|HOME' \
  "$root/Panel.qml" "$root/BarWidget.qml" "$root/Service.qml" "$root/GitHubApi.qml"
! rg -n 'https://github\.com/(notifications|pulls|issues)' "$root/Panel.qml"
rg -Fq 'openUrl: github.navigationHandles.notifications || ""' "$root/Panel.qml"
rg -Fq 'import Omarchy.PluginPresentation 1.0' "$root/Panel.qml"
rg -Fq 'runtime.execute("bash", "gh", arguments)' "$root/GitHubApi.qml"
! rg -Fq 'runtime.invoke("bash.execute"' "$root/GitHubApi.qml"
! rg -Fq 'omarchy-github-fetch' "$root/Service.qml" "$root/GitHubApi.qml"
rg -Fq 'runtime.hasPermission("bash.execute", "run")' "$root/Panel.qml"
rg -Fq 'runtime.hasPermission("bash.execute", "run")' "$root/BarWidget.qml"
! rg -Fq 'runtime.hasPermission("remote-account.' "$root/Panel.qml" "$root/BarWidget.qml" "$root/Service.qml"
rg -Fq 'runtime.invoke("external.open-uri.https", "open"' "$root/Panel.qml"
rg -Fq 'url: resource,' "$root/Panel.qml"
! rg -Fq 'uriHandle' "$root/Panel.qml"
! rg -Fq 'runtime.invokeAction' "$root/Panel.qml"
rg -Fq 'opened && canMarkRead && notificationId !== ""' "$root/Panel.qml"
rg -Fq 'github.markNotificationRead(notificationId)' "$root/Panel.qml"
rg -Fq 'runtime.updateSettings(entry)' "$root/Panel.qml"
rg -Fq 'runtime.requestSurfaceIntent("github", "toggle")' "$root/BarWidget.qml"
rg -Fq 'if (mouse.button === Qt.RightButton || mouse.button === Qt.MiddleButton) github.refresh()' "$root/BarWidget.qml"
rg -Fq 'github.alarming && !settings.iconAlwaysUnlit' "$root/BarWidget.qml"
rg -Fq 'actionRepoLimit: intSetting("actionScanRepoLimit", 15, 5, 200)' "$root/Service.qml"
rg -Fq 'actionConcurrency: intSetting("actionScanConcurrency", 6, 1, 12)' "$root/Service.qml"
! rg -q 'actionRepositoryLimit|^[[:space:]]*concurrency:' "$root/Service.qml"
[[ ! -e "$root/qs" ]]
[[ ! -e "$root/Process.qml" ]]
[[ ! -e "$root/StdioCollector.qml" ]]
[[ ! -e "$root/IpcHandler.qml" ]]
[[ ! -e "$root/GitHubProcess.qml" ]]

printf '%s\n' 'ok - GitHub v2 broker boundary'
