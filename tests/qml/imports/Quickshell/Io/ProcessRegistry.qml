pragma Singleton
import QtQml

QtObject {
  property var processes: []

  function add(process) {
    processes = processes.concat([process])
  }

  function remove(process) {
    var remaining = []
    for (var i = 0; i < processes.length; i++) {
      if (processes[i] !== process) remaining.push(processes[i])
    }
    processes = remaining
  }
}
