#!/bin/bash
# Shows a macOS notification via terminal-notifier. Clicking it opens/focuses
# this project's folder in VS Code via the vscode:// URI scheme, handled
# directly by the running VS Code app (no extra CLI process spawned).
# Usage: notify.sh "<message>" ["<sound file>"]

set -euo pipefail

message="$1"
sound="${2:-}"

terminal-notifier \
  -message "$message" \
  -title "Claude Code" \
  -open "vscode://file$PWD" \
  -contentImage "/Applications/Visual Studio Code.app/Contents/Resources/Code.icns"

if [ -n "$sound" ]; then
  afplay "$sound"
fi
