pragma Singleton
import QtQml

QtObject {
  readonly property var font: ({ family: "sans", icon: 16, display: 24, title: 18, body: 14, bodySmall: 12, caption: 10 })
  readonly property var spacing: ({ controlPaddingY: 2 })
  readonly property real cornerRadius: 4
  readonly property real normalBorderWidth: 1
  function space(value) { return Number(value) }
}
