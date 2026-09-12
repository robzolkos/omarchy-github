#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
QML_TEST_RUNNER=${QML_TEST_RUNNER:-}

if [[ -z $QML_TEST_RUNNER ]]; then
  if [[ -x /usr/lib/qt6/bin/qmltestrunner ]]; then
    QML_TEST_RUNNER=/usr/lib/qt6/bin/qmltestrunner
  elif command -v qmltestrunner >/dev/null 2>&1; then
    QML_TEST_RUNNER=$(command -v qmltestrunner)
  else
    echo "Qt 6 qmltestrunner unavailable; skipping QML behavior tests"
    exit 0
  fi
fi

QT_QPA_PLATFORM=offscreen \
QT_QUICK_BACKEND=software \
"$QML_TEST_RUNNER" \
  -input "$ROOT/tests/qml" \
  -import "$ROOT/tests/qml/imports" \
  -o -,txt
