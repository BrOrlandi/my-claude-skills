#!/usr/bin/env bash
# Keeps the Mac awake while Claude Code is working on a turn.
#
# Called from UserPromptSubmit (turn starts) and from PreToolUse (heartbeat:
# while Claude keeps calling tools, it is still working). It is idempotent —
# it only (re)starts caffeinate when the current assertion is stale or dead.
#
# Three layers make sure the caffeinate process is never orphaned:
#   1. -w <claude pid>     -> dies with Claude if it is closed, killed or hangs
#   2. -t $TTL             -> backstop: expires on its own if nothing kills it
#   3. caffeinate-release.sh -> kills it on Stop and on SessionEnd
#
# macOS only: `caffeinate` does not exist on Linux or Windows.

TTL=1800    # 30 min backstop
RENEW=300   # renew the assertion once it is older than 5 min

# Walk up the process tree until we find the `claude` process of this session.
cpid=$PPID
while [ "${cpid:-0}" -gt 1 ]; do
  case "$(ps -o comm= -p "$cpid" 2>/dev/null)" in
    *claude) break ;;
  esac
  cpid=$(ps -o ppid= -p "$cpid" 2>/dev/null | tr -d ' ')
done
[ "${cpid:-0}" -gt 1 ] || exit 0

pf="/tmp/claude-caffeinate-$cpid.pid"
now=$(date +%s)

if [ -f "$pf" ]; then
  read -r old started < "$pf"
  if kill -0 "$old" 2>/dev/null; then
    [ $((now - ${started:-0})) -lt "$RENEW" ] && exit 0
    kill "$old" 2>/dev/null
  fi
fi

nohup caffeinate -dimsu -w "$cpid" -t "$TTL" >/dev/null 2>&1 &
echo "$! $now" > "$pf"
disown 2>/dev/null
exit 0
