#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test tool integration_test packages/nextbell_platform/lib packages/nextbell_platform/pigeons
flutter analyze
flutter test
(cd android && ./gradlew :nextbell_platform:testDebugUnitTest --console=plain)
