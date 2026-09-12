pragma Singleton
import QtQml

QtObject {
  property var execCalls: []

  function reset() { execCalls = [] }
  function execArgv(argv) { execCalls = execCalls.concat([argv]) }
  function wheelSteps(remainder, angle) { return ({ steps: 0, remainder: remainder + angle }) }
}
