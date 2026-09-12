pragma Singleton
import QtQml

QtObject {
  property var execCalls: []

  function reset() { execCalls = [] }
  function execDetached(argv) { execCalls = execCalls.concat([argv]) }
}
