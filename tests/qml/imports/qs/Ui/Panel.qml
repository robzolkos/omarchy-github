import QtQuick

Item {
  property string moduleName: ""
  property string ipcTarget: ""
  property bool manageIpc: true
  property var bar: null
  property var settings: ({})
  property bool opened: false
  property int closeCalls: 0

  function open() { opened = true }
  function close() { closeCalls++; opened = false }
  function toggle() { opened = !opened }
}
