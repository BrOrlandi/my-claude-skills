#!/usr/bin/env bash
# Show the review status on the Slack message that handed over the PR, as one reaction from the reviewer:
#   reviewing ⏳  ·  changes 🔄 (findings for the author)  ·  approved ✅
# Setting a status removes the other two, so the message carries only the current one.
#
# Usage: slack-status.sh <channel id> <message ts> <reviewing|changes|approved>
# Never fails the caller: a Slack error is printed to stderr and the script exits 0.
set -uo pipefail

channel="$1"; ts="$2"; status="$3"
# Plain case instead of an associative array: macOS /bin/bash is 3.2.
case "$status" in
    reviewing) want=hourglass_flowing_sand ;;
    changes)   want=arrows_counterclockwise ;;
    approved)  want=white_check_mark ;;
    *) echo "unknown status: $status" >&2; exit 0 ;;
esac

export SLACKCLI_NO_UPDATE_NOTIFIER=1
for name in hourglass_flowing_sand arrows_counterclockwise white_check_mark; do
    [[ "$name" == "$want" ]] && continue
    slackcli messages unreact --channel-id "$channel" --timestamp "$ts" --emoji "$name" >/dev/null 2>&1 || true
done
slackcli messages react --channel-id "$channel" --timestamp "$ts" --emoji "$want" >/dev/null 2>&1 \
    || echo "slack-status: could not add :$want: to $channel/$ts" >&2
exit 0
