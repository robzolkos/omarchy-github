import QtQuick

Rectangle {
  property var bar: null
  property var owner: null
  property var anchorItem: null
  property var focusTarget: null
  property var options: []
  property var borderSpec: null
  property Component trailingControl: null
  property Component iconComponent: null
  property string text: ""
  property string title: ""
  property string meta: ""
  property string label: ""
  property string description: ""
  property string placeholderText: ""
  property string value: ""
  property string iconText: ""
  property string tooltipText: ""
  property string fontFamily: ""
  property color foreground: "white"
  property color hoverColor: "transparent"
  property color background: "transparent"
  property color accent: "white"
  property bool active: false
  property bool blocked: false
  property bool bordered: false
  property bool checked: false
  property bool focusable: false
  property bool hasCursor: false
  property bool open: false
  property bool popupOpen: false
  property bool selected: false
  property bool showLabel: true
  property real contentWidth: 0
  property real contentHeight: 0
  property real fontSize: 10
  property real verticalPadding: 0

  signal pressed(int buttonCode)
  signal moveRequested(real dx, real dy)
  signal activateRequested()
  signal closeRequested()
  signal tabRequested(int direction)
  signal textKey(string text)
  signal clicked()
  signal changed(string value)

  function close() { popupOpen = false }
  function fittedContentWidth(value) { return value }
  function fittedContentHeight(value, maximum) { return Math.min(value, maximum) }
}
