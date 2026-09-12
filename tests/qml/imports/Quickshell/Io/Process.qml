import QtQml

QtObject {
  id: root

  property bool running: false
  property var command: []
  property var stdout: null
  property var stderr: null

  signal exited(int exitCode)

  function complete(exitCode, stdoutText, stderrText) {
    if (stdout) {
      stdout.text = String(stdoutText || "")
      stdout.streamFinished()
    }
    if (stderr) {
      stderr.text = String(stderrText || "")
      stderr.streamFinished()
    }
    running = false
    exited(exitCode)
  }

  Component.onCompleted: ProcessRegistry.add(root)
  Component.onDestruction: ProcessRegistry.remove(root)
}
