#!/bin/bash
# Fetch and display all Jira activities (create, edit, comment, status change, etc.)
# Usage: jira_activity_report.sh [DAYS] [PROJECT]
#   DAYS    - Number of days to look back (default: 3)
#   PROJECT - Jira project key to filter (optional, searches all projects if omitted)
#
# Authentication: Uses jira CLI config (~/.config/.jira/.config.yml) + JIRA_API_TOKEN env var
#
# Output: Grouped by user, showing all activities with timestamps

set -euo pipefail

DAYS="${1:-3}"
PROJECT="${2:-}"

# Resolve credentials
JIRA_CONFIG="${JIRA_CONFIG_FILE:-$HOME/.config/.jira/.config.yml}"
if [ ! -f "$JIRA_CONFIG" ]; then
  echo "Error: No jira CLI config found at $JIRA_CONFIG" >&2
  echo "Run 'jira init' to configure." >&2
  exit 1
fi

JIRA_URL=$(python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    cfg = yaml.safe_load(f)
print(cfg.get('server', '').rstrip('/'))
" "$JIRA_CONFIG")

JIRA_EMAIL=$(python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    cfg = yaml.safe_load(f)
print(cfg.get('login', ''))
" "$JIRA_CONFIG")

: "${JIRA_API_TOKEN:?JIRA_API_TOKEN env var is required}"

if [ -z "$JIRA_URL" ] || [ -z "$JIRA_EMAIL" ]; then
  echo "Error: Could not read server/login from $JIRA_CONFIG" >&2
  exit 1
fi

# Build JQL
JQL="updated >= -${DAYS}d ORDER BY updated DESC"
if [ -n "$PROJECT" ]; then
  JQL="project = ${PROJECT} AND updated >= -${DAYS}d ORDER BY updated DESC"
fi

# Temp dirs
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Step 1: Fetch all issues (paginated)
echo "Buscando issues atualizadas nos ultimos ${DAYS} dias..." >&2

ALL_ISSUES="[]"
NEXT_TOKEN=""

while true; do
  if [ -z "$NEXT_TOKEN" ]; then
    PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'jql': '''$JQL''',
    'maxResults': 50,
    'fields': ['summary','status','assignee','creator','created','updated','issuetype','comment']
}))
")
  else
    PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'jql': '''$JQL''',
    'maxResults': 50,
    'fields': ['summary','status','assignee','creator','created','updated','issuetype','comment'],
    'nextPageToken': '$NEXT_TOKEN'
}))
")
  fi

  RESULT=$(curl -s -X POST -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    -H "Content-Type: application/json" \
    "$JIRA_URL/rest/api/3/search/jql" \
    -d "$PAYLOAD")

  # Check for errors
  ERROR=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); msgs=d.get('errorMessages',[]); print(msgs[0] if msgs else '')" 2>/dev/null || echo "")
  if [ -n "$ERROR" ]; then
    echo "Error from Jira API: $ERROR" >&2
    exit 1
  fi

  PAGE_ISSUES=$(echo "$RESULT" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('issues',[])))")
  ALL_ISSUES=$(python3 -c "import sys,json; a=json.loads(sys.argv[1]); b=json.loads(sys.argv[2]); print(json.dumps(a+b))" "$ALL_ISSUES" "$PAGE_ISSUES")

  IS_LAST=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('isLast', True))")
  if [ "$IS_LAST" = "True" ]; then
    break
  fi

  NEXT_TOKEN=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('nextPageToken',''))")
  if [ -z "$NEXT_TOKEN" ]; then
    break
  fi
done

echo "$ALL_ISSUES" > "$TMPDIR/issues.json"

NUM_ISSUES=$(python3 -c "import json; print(len(json.loads(open('$TMPDIR/issues.json').read())))")
echo "Issues encontradas: $NUM_ISSUES" >&2

# Step 2: Fetch changelogs in parallel
echo "Buscando changelogs..." >&2
mkdir -p "$TMPDIR/changelogs"

python3 -c "import json; issues=json.loads(open('$TMPDIR/issues.json').read()); print('\n'.join(i['key'] for i in issues))" > "$TMPDIR/keys.txt"

while IFS= read -r KEY; do
  curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    "$JIRA_URL/rest/api/3/issue/$KEY/changelog" \
    -o "$TMPDIR/changelogs/$KEY.json" &
  # Limit parallel requests
  if (( $(jobs -r | wc -l) >= 10 )); then
    wait -n 2>/dev/null || wait
  fi
done < "$TMPDIR/keys.txt"
wait

echo "Processando atividades..." >&2
echo ""

# Step 3: Process and display
python3 - "$TMPDIR" "$DAYS" << 'PYEOF'
import json, os, re, sys
from datetime import datetime, timedelta, timezone
from collections import defaultdict

tmpdir = sys.argv[1]
days = int(sys.argv[2])

def parse_dt(s):
    s = re.sub(r'(\d{2})(\d{2})$', r'\1:\2', s)
    return datetime.fromisoformat(s)

with open(f'{tmpdir}/issues.json') as f:
    issues = json.load(f)

cutoff = datetime.now(timezone.utc) - timedelta(days=days)
activities = []

ACTION_MAP = {
    'status': lambda f, t: ('Mudou status', f'{f} -> {t}'),
    'assignee': lambda f, t: ('Mudou responsavel', f'{f or "Ninguem"} -> {t or "Ninguem"}'),
    'summary': lambda f, t: ('Editou titulo', f'"{f}" -> "{t}"'),
    'description': lambda f, t: ('Editou descricao', ''),
    'priority': lambda f, t: ('Mudou prioridade', f'{f} -> {t}'),
    'Sprint': lambda f, t: ('Mudou sprint', f'{f or "Nenhuma"} -> {t or "Nenhuma"}'),
    'labels': lambda f, t: ('Mudou labels', f'{f or "Nenhuma"} -> {t or "Nenhuma"}'),
    'Rank': lambda f, t: ('Reordenou no board', ''),
    'resolution': lambda f, t: ('Mudou resolucao', f'{f or "Nenhuma"} -> {t or "Nenhuma"}'),
    'issuetype': lambda f, t: ('Mudou tipo', f'{f} -> {t}'),
    'Attachment': lambda f, t: ('Adicionou anexo', t),
    'Link': lambda f, t: ('Adicionou link', t),
    'Component': lambda f, t: ('Mudou componente', f'{f or "Nenhum"} -> {t or "Nenhum"}'),
    'parent': lambda f, t: ('Mudou parent', f'{f or "Nenhum"} -> {t or "Nenhum"}'),
    'IssueParentAssociation': lambda f, t: ('Mudou parent', f'{f or "Nenhum"} -> {t or "Nenhum"}'),
    'RemoteWorkItemLink': lambda f, t: ('Adicionou link remoto', t),
    'Fix Version': lambda f, t: ('Mudou versao', f'{f or "Nenhuma"} -> {t or "Nenhuma"}'),
    'Story Points': lambda f, t: ('Mudou story points', f'{f or 0} -> {t or 0}'),
    'story_points': lambda f, t: ('Mudou story points', f'{f or 0} -> {t or 0}'),
    'duedate': lambda f, t: ('Mudou due date', f'{f or "Nenhuma"} -> {t or "Nenhuma"}'),
}

def extract_text_from_adf(node):
    if not isinstance(node, dict):
        return ''
    if node.get('type') == 'text':
        return node.get('text', '')
    result = ''
    for child in node.get('content', []):
        result += extract_text_from_adf(child)
    return result

for issue in issues:
    key = issue['key']
    summary = issue['fields']['summary']
    created_str = issue['fields']['created']
    creator = issue['fields'].get('creator', {})
    creator_name = creator.get('displayName', 'Unknown') if creator else 'Unknown'
    issue_type = issue['fields']['issuetype']['name']

    created_dt = parse_dt(created_str)
    if created_dt.astimezone(timezone.utc) >= cutoff:
        activities.append({
            'time': created_str, 'user': creator_name, 'issue': key,
            'summary': summary, 'action': 'Criou issue',
            'detail': f'Tipo: {issue_type}'
        })

    # Changelog
    cl_path = f'{tmpdir}/changelogs/{key}.json'
    histories = []
    if os.path.exists(cl_path):
        try:
            with open(cl_path) as f:
                cl_data = json.load(f)
            histories = cl_data.get('values', [])
        except:
            pass

    for history in histories:
        h_time = history['created']
        h_dt = parse_dt(h_time)
        if h_dt.astimezone(timezone.utc) < cutoff:
            continue
        h_user = history.get('author', {}).get('displayName', 'Unknown')
        for item in history.get('items', []):
            field = item['field']
            from_val = item.get('fromString', '') or ''
            to_val = item.get('toString', '') or ''

            if field in ACTION_MAP:
                action, detail = ACTION_MAP[field](from_val, to_val)
            else:
                action = f'Editou {field}'
                detail = f'{from_val} -> {to_val}' if from_val or to_val else ''

            activities.append({
                'time': h_time, 'user': h_user, 'issue': key,
                'summary': summary, 'action': action, 'detail': detail
            })

    # Comments
    comments = issue['fields'].get('comment', {}).get('comments', [])
    for comment in comments:
        c_time = comment['created']
        c_dt = parse_dt(c_time)
        if c_dt.astimezone(timezone.utc) < cutoff:
            continue
        c_user = comment.get('author', {}).get('displayName', 'Unknown')
        text = extract_text_from_adf(comment.get('body', {}))
        text = (text[:80] + '...') if len(text) > 80 else text
        activities.append({
            'time': c_time, 'user': c_user, 'issue': key,
            'summary': summary, 'action': 'Comentou', 'detail': text
        })

# Sort
activities.sort(key=lambda x: parse_dt(x['time']), reverse=True)

# Group by user
by_user = defaultdict(list)
for a in activities:
    by_user[a['user']].append(a)

print(f"ATIVIDADES NO JIRA - ULTIMOS {days} DIAS")
print(f"Periodo: {cutoff.strftime('%d/%m/%Y %H:%M')} UTC ate agora")
print(f"Issues atualizadas: {len(issues)} | Total de atividades: {len(activities)}")
print("=" * 95)

for user, acts in sorted(by_user.items()):
    print(f"\n>>> {user} ({len(acts)} atividades)")

    action_counts = defaultdict(int)
    for a in acts:
        action_counts[a['action']] += 1
    summary_parts = [f"{k}: {v}" for k, v in sorted(action_counts.items())]
    print(f"    Resumo: {' | '.join(summary_parts)}")
    print("-" * 95)

    for a in acts:
        ts = parse_dt(a['time'])
        ts_str = ts.strftime('%d/%m %H:%M')
        detail_str = f'  [{a["detail"]}]' if a['detail'] else ''
        print(f"  {ts_str}  {a['issue']:>8}  {a['action']}{detail_str}")
        print(f"                        -> {a['summary']}")

print(f"\n{'=' * 95}")
PYEOF
