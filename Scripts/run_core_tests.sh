#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/manual"
mkdir -p "$OUT"

# Prefer the active developer directory (Xcode on CI after xcode-select).
# Hardcoding CommandLineTools/SDKs/MacOSX.sdk breaks when that SDK is newer
# than the Swift compiler on PATH.
SWIFTC="${SWIFTC:-$(xcrun --find swiftc)}"
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
TARGET="${SWIFT_TARGET:-$(uname -m)-apple-macos14.0}"

"$SWIFTC" -sdk "$SDK" -target "$TARGET" -parse-as-library \
  -o "$OUT/CoreTests" \
  "$ROOT/ModelMonitor/Features/Grok/Usage/UsageModels.swift" \
  "$ROOT/ModelMonitor/Features/Grok/Usage/UsageClient.swift" \
  "$ROOT/ModelMonitor/Features/Grok/Usage/DailyUsageBuilder.swift" \
  "$ROOT/ModelMonitor/Features/Grok/History/ExportService.swift" \
  "$ROOT/ModelMonitor/Features/Shared/Percent.swift" \
  "$ROOT/ModelMonitor/Features/Shared/Format.swift" \
  "$ROOT/ModelMonitor/Features/Shared/JSON.swift" \
  "$ROOT/ModelMonitor/Features/Shared/ColorPalette.swift" \
  "$ROOT/ModelMonitor/Features/Shared/ISO8601.swift" \
  "$ROOT/ModelMonitor/Features/Shared/UsageError.swift" \
  "$ROOT/Tests/Manual/CoreTestsMain.swift"

"$OUT/CoreTests"
