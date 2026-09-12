pragma Singleton
import QtQml

QtObject {
  function flat(color, width) { return ({ color: color, width: width }) }
  function none() { return ({}) }
}
