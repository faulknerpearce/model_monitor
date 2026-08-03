#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
OUT="$ROOT/.build/manual"
mkdir -p "$OUT"

swiftc -sdk "$SDK" -target arm64-apple-macos14.0 -parse-as-library \
  -o "$OUT/CoreTests" \
  "$ROOT/GrokMonitor/Features/Grok/Usage/UsageModels.swift" \
  "$ROOT/GrokMonitor/Features/Grok/Usage/UsageClient.swift" \
  "$ROOT/GrokMonitor/Features/Grok/Usage/DailyUsageBuilder.swift" \
  "$ROOT/GrokMonitor/Features/Grok/History/ExportService.swift" \
  "$ROOT/GrokMonitor/Features/Shared/Percent.swift" \
  "$ROOT/Tests/Manual/CoreTestsMain.swift"

"$OUT/CoreTests"
