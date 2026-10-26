#!/bin/bash
# Keeps the Mac awake for the duration of a Claude Code session's active turns.
# Invoked from settings.json: UserPromptSubmit -> start, Stop -> stop.
# Scoped per session_id so concurrent sessions don't kill each other's caffeinate.

set -euo pipefail

action="$1"
session_id=$(jq -r '.session_id')
pidfile="/tmp/claude-caffeinate-$session_id.pid"

case "$action" in
  start)
    if [ ! -f "$pidfile" ] || ! kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
      # Redirect all fds and use nohup so the backgrounded caffeinate doesn't
      # hold the hook's stdio pipes open, which would block the hook runner.
      nohup caffeinate -ims -t 1800 >/dev/null 2>&1 </dev/null &
      echo $! > "$pidfile"
    fi
    ;;
  stop)
    if [ -f "$pidfile" ]; then
      kill "$(cat "$pidfile")" 2>/dev/null || true
      rm -f "$pidfile"
    fi
    ;;
  *)
    echo "usage: $0 {start|stop}" >&2
    exit 1
    ;;
esac
