#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
OUT="$ROOT/.build/manual"
mkdir -p "$OUT"

swiftc -sdk "$SDK" -target arm64-apple-macos14.0 -parse-as-library \
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
  "$ROOT/Tests/Manual/CoreTestsMain.swift"

"$OUT/CoreTests"
