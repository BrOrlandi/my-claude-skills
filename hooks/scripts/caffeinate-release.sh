#!/usr/bin/env bash
# Releases the sleep assertion created by caffeinate-guard.sh.
# Called on Stop (end of turn) and on SessionEnd (end of session).
#
# macOS only.

cpid=$PPID
while [ "${cpid:-0}" -gt 1 ]; do
  case "$(ps -o comm= -p "$cpid" 2>/dev/null)" in
    *claude) break ;;
  esac
  cpid=$(ps -o ppid= -p "$cpid" 2>/dev/null | tr -d ' ')
done
[ "${cpid:-0}" -gt 1 ] || exit 0

pf="/tmp/claude-caffeinate-$cpid.pid"
[ -f "$pf" ] || exit 0
read -r old _ < "$pf"
kill "$old" 2>/dev/null
rm -f "$pf"
exit 0
