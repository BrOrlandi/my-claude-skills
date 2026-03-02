---
name: slack
description: Send messages, upload files and images, read conversations, react to messages, and manage Slack workspaces using SlackCLI. Use when the user wants to interact with Slack — send a message, share a file, upload images or screenshots, read channel history, find a user, react to a message, or check workspace auth.
argument-hint: "[send|read|upload|find|react|auth] [message, file path, or target]"
---

# Slack Skill

You are a Slack automation assistant. You help users send messages, read conversations, upload files and images, react to messages, find users/channels, and manage workspace authentication — all through the `slackcli` CLI and `curl`.

## Arguments

- `$ARGUMENTS` (optional): The action and target. Examples:
  - `send @vinicius "Hello!"` — send a DM
  - `send #general "Deploy done"` — send to a channel
  - `read #general` — read channel history
  - `read #general --thread 1234567890.123456` — read a thread
  - `upload @vinicius ./report.pdf` — upload a file
  - `find @john` — find a user
  - `find #proj` — find channels matching "proj"
  - `react #general thumbsup` — react to the latest message
  - `auth` — manage workspaces

If no arguments are provided, ask the user what they want to do.

## Step 1: Check Prerequisites

### 1.1 Verify slackcli is installed

Run:
```bash
which slackcli
```

If **not found**, tell the user to install it:

> `slackcli` is not installed. Install it from the GitHub releases:
>
> **macOS (Apple Silicon):**
> ```bash
> curl -L https://github.com/shaharia-lab/slackcli/releases/latest/download/slackcli_darwin_arm64.tar.gz | tar xz
> sudo mv slackcli /usr/local/bin/
> ```
>
> **macOS (Intel):**
> ```bash
> curl -L https://github.com/shaharia-lab/slackcli/releases/latest/download/slackcli_darwin_amd64.tar.gz | tar xz
> sudo mv slackcli /usr/local/bin/
> ```
>
> **Linux:**
> ```bash
> curl -L https://github.com/shaharia-lab/slackcli/releases/latest/download/slackcli_linux_amd64.tar.gz | tar xz
> sudo mv slackcli /usr/local/bin/
> ```

After installation is confirmed, proceed.

### 1.2 Check for authenticated workspaces

Run:
```bash
slackcli auth list
```

If there are **no workspaces configured**, proceed to the full Slack App setup guide in Step 1.3.

If workspaces exist, skip to Step 2.

### 1.3 Full Slack App Setup Guide (Step-by-Step)

Walk the user through the entire process interactively. Ask confirmation at each step before proceeding to the next.

#### Step A: Create a Slack App

1. Tell the user to open this URL in their browser: **https://api.slack.com/apps**
2. Click **"Create New App"**
3. Choose **"From scratch"**
4. Enter an App Name (e.g., "My SlackCLI") and select the workspace
5. Click **"Create App"**

#### Step B: Configure OAuth Scopes

1. In the app settings, go to **"OAuth & Permissions"** in the left sidebar
2. Scroll to **"User Token Scopes"** (NOT Bot Token Scopes)
3. Click **"Add an OAuth Scope"** and add ALL of the following scopes one by one:

| Scope | Purpose |
|---|---|
| `channels:history` | Read public channel messages |
| `channels:read` | List public channels |
| `chat:write` | Send messages |
| `files:read` | Access file info |
| `files:write` | Upload files |
| `groups:history` | Read private channel messages |
| `groups:read` | List private channels |
| `im:history` | Read direct messages |
| `im:read` | List DM conversations |
| `mpim:history` | Read group DMs |
| `mpim:read` | List group DM conversations |
| `reactions:write` | Add reactions to messages |
| `users:read` | Look up user information |

#### Step C: Install the App to the Workspace

1. Scroll to the top of the **"OAuth & Permissions"** page
2. Click **"Install to Workspace"** (or **"Reinstall to Workspace"** if updating scopes)
3. Review the permissions and click **"Allow"**
4. Copy the **"User OAuth Token"** that appears (starts with `xoxp-`)

**Important:** This is a **User OAuth Token**, not a Bot token. The user token is required for `slackcli` to act on behalf of the user.

#### Step D: Login with slackcli

Run the following command, replacing `<TOKEN>` with the copied token and `<WORKSPACE_NAME>` with a friendly name:

```bash
slackcli auth login --token "<TOKEN>" --workspace-name "<WORKSPACE_NAME>"
```

Then verify:
```bash
slackcli auth list
```

The workspace should appear in the list. If the user has multiple workspaces, they can set the default:
```bash
slackcli auth set-default --workspace-name "<WORKSPACE_NAME>"
```

## Step 2: Determine Action

Parse `$ARGUMENTS` to determine the action. The first word is the action:

| First word | Action |
|---|---|
| `send` | Send a message |
| `read` | Read conversation history |
| `upload` | Upload a file |
| `find` | Find a user or channel |
| `react` | React to a message |
| `auth` | Manage auth/workspaces |

If no action is clear from the arguments, ask the user what they want to do.

## Step 3: Resolve Recipient

For **send**, **read**, **upload**, and **react** actions, resolve the target to a Slack channel ID.

### 3.1 Channel target (starts with `#`)

Search for the channel:
```bash
slackcli conversations list --types public_channel,private_channel | grep -i "<channel_name>"
```

Extract the channel ID from the output.

### 3.2 User target (starts with `@`)

Find the user's DM channel:
```bash
slackcli conversations list --types im --json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for ch in data:
    if '<username>' in str(ch).lower():
        print(json.dumps(ch, indent=2))
"
```

If that doesn't find the user directly, list users first:
```bash
slackcli users list --json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for u in data:
    name = str(u.get('name', '') or u.get('real_name', '')).lower()
    if '<username>' in name:
        print(u.get('id'), '-', u.get('real_name', ''), '-', u.get('name', ''))
"
```

Then find or open the DM conversation with that user ID.

### 3.3 Channel not found

If a channel is not found in the list, it may be because:
- The Slack app hasn't been added to that channel (especially private channels)
- The channel name is slightly different

In this case:
1. Ask the user to provide the channel ID directly (they can find it in the channel's settings in Slack)
2. Or ask them to add the Slack app to the channel first

### 3.4 Ambiguous target

If multiple matches are found, show them to the user and ask which one they mean.

### 3.5 Direct ID

If the user provides a channel ID directly (starts with `C`, `D`, or `G`), use it as-is. This is useful when channels don't appear in the list (e.g., private channels the app hasn't been added to).

## Step 4a: Send Message

```bash
slackcli messages send --recipient-id <CHANNEL_ID> --message "<text>"
```

For **multi-line messages**, use bash `$'...'` syntax:
```bash
slackcli messages send --recipient-id <CHANNEL_ID> --message $'Line 1\nLine 2\nLine 3'
```

For **thread replies**, add `--thread-ts`:
```bash
slackcli messages send --recipient-id <CHANNEL_ID> --message "<text>" --thread-ts "<timestamp>"
```

### Capturing the message timestamp

When sending a message that will later receive thread replies (e.g., file uploads in thread), capture the timestamp from the output:

```bash
MSG_OUTPUT=$(slackcli messages send --recipient-id <CHANNEL_ID> --message "<text>" 2>&1)
MSG_TS=$(echo "$MSG_OUTPUT" | sed -n 's/.*Message timestamp: //p')
```

The `MSG_TS` value (e.g., `1772479430.645059`) is needed to send thread replies or upload files to the thread.

**Important:** Always confirm the message content and recipient with the user before sending.

### Sending a message with file attachments

When the user wants to send a message along with images or files, follow this pattern:

1. **Show the message** to the user for approval before sending
2. **Ask where to put the files**: in the thread (recommended — keeps the channel clean) or directly in the channel
3. **Send the text message** first and capture its timestamp
4. **Upload files** to the thread using the captured timestamp (see Step 4c)

This is the recommended flow for sharing screenshots, reports, or any files alongside a text message.

### Test in DM first

When the user is sending to a public/shared channel, **suggest sending to their own DM first** as a test. This lets them preview how the message and attachments will look before posting publicly. After confirmation, send to the actual channel.

To find the user's own DM:
```bash
slackcli conversations list --types im | grep -i "<user_name>"
```

## Step 4b: Read Conversation

```bash
slackcli conversations read <CHANNEL_ID> --limit <N>
```

Default limit is 10 messages. The user can request more.

For **thread reading**:
```bash
slackcli conversations read <CHANNEL_ID> --thread-ts <TIMESTAMP> --limit <N>
```

For **JSON output** (useful for extracting timestamps, user IDs, etc.):
```bash
slackcli conversations read <CHANNEL_ID> --limit <N> --json
```

When presenting messages:
- Format them readably with sender name, timestamp, and content
- For long conversations, summarize and highlight key points
- Mention thread count if messages have replies

## Step 4c: Upload File

File uploads use the new Slack API (3-step flow) via `curl`. The old `files.upload` endpoint is deprecated.

### Extract the token from slackcli config:

The `workspaces.json` file uses a dict keyed by workspace ID. Extract the token like this:

```bash
SLACK_TOKEN=$(python3 -c "
import json, os
with open(os.path.expanduser('~/.config/slackcli/workspaces.json')) as f:
    data = json.load(f)
ws = data['workspaces']
for k, v in ws.items():
    print(v['token'])
    break
")
```

If the user has **multiple workspaces**, filter by workspace name to get the correct token.

### Upload a single file (3-step flow)

```bash
FILE_PATH="<path_to_file>"
FILE_NAME=$(basename "$FILE_PATH")
FILE_SIZE=$(wc -c < "$FILE_PATH" | tr -d ' ')
CHANNEL_ID="<target_channel_id>"

# Step 1: Get upload URL
UPLOAD_RESPONSE=$(curl -s -X POST "https://slack.com/api/files.getUploadURLExternal" \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "filename=$FILE_NAME" \
  --data-urlencode "length=$FILE_SIZE")

UPLOAD_URL=$(echo "$UPLOAD_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('upload_url',''))")
FILE_ID=$(echo "$UPLOAD_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('file_id',''))")

# Step 2: Upload the file content
curl -s -X POST "$UPLOAD_URL" -F "file=@$FILE_PATH" > /dev/null

# Step 3: Complete the upload
curl -s -X POST "https://slack.com/api/files.completeUploadExternal" \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"files\": [{\"id\": \"$FILE_ID\", \"title\": \"$TITLE\"}], \"channel_id\": \"$CHANNEL_ID\"}"
```

### Upload file to a thread

To upload a file as a **thread reply** instead of a top-level message, add `thread_ts` to the Step 3 payload:

```bash
curl -s -X POST "https://slack.com/api/files.completeUploadExternal" \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"files\": [{\"id\": \"$FILE_ID\", \"title\": \"$TITLE\"}], \"channel_id\": \"$CHANNEL_ID\", \"thread_ts\": \"$THREAD_TS\"}"
```

### Upload multiple files in a loop

When uploading multiple files (e.g., screenshots), use a loop. Each file goes through the full 3-step flow individually:

```bash
FILES=(
  "/path/to/file1.png|Title for file 1"
  "/path/to/file2.png|Title for file 2"
)

for entry in "${FILES[@]}"; do
  FILE_PATH="${entry%%|*}"
  TITLE="${entry##*|}"
  FILE_NAME=$(basename "$FILE_PATH")
  FILE_SIZE=$(wc -c < "$FILE_PATH" | tr -d ' ')

  # Step 1: Get upload URL
  UPLOAD_RESPONSE=$(curl -s -X POST "https://slack.com/api/files.getUploadURLExternal" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "filename=$FILE_NAME" \
    --data-urlencode "length=$FILE_SIZE")

  UPLOAD_URL=$(echo "$UPLOAD_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('upload_url',''))")
  FILE_ID=$(echo "$UPLOAD_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('file_id',''))")

  # Step 2: Upload file content
  curl -s -X POST "$UPLOAD_URL" -F "file=@$FILE_PATH" > /dev/null

  # Step 3: Complete upload (with optional thread_ts)
  COMPLETE_RESPONSE=$(curl -s -X POST "https://slack.com/api/files.completeUploadExternal" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"files\": [{\"id\": \"$FILE_ID\", \"title\": \"$TITLE\"}], \"channel_id\": \"$CHANNEL_ID\", \"thread_ts\": \"$THREAD_TS\"}")

  OK=$(echo "$COMPLETE_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('ok', False))")
  if [ "$OK" = "True" ]; then
    echo "✅ Uploaded: $TITLE"
  else
    echo "❌ Failed: $COMPLETE_RESPONSE"
  fi
done
```

After upload, show the file permalink from the response if available.

**Important:** Always confirm the file and recipient with the user before uploading.

## Step 4d: React to Message

To add a reaction to a message:

```bash
slackcli messages react --channel-id <CHANNEL_ID> --timestamp <MESSAGE_TS> --emoji <EMOJI_NAME>
```

- `EMOJI_NAME` is without colons (e.g., `thumbsup`, `eyes`, `rocket`, `white_check_mark`)
- `MESSAGE_TS` is the message timestamp (e.g., `1234567890.123456`)

**Common flow:** If the user says "react to the last message in #general with :thumbsup:", first read the channel to get the latest message timestamp, then react.

```bash
# Get latest message timestamp
LATEST_TS=$(slackcli conversations read <CHANNEL_ID> --limit 1 --json | python3 -c "
import json, sys
msgs = json.load(sys.stdin)
if msgs:
    print(msgs[0].get('ts', ''))
")

# React
slackcli messages react --channel-id <CHANNEL_ID> --timestamp "$LATEST_TS" --emoji thumbsup
```

## Step 4e: Find User/Channel

### Find channels:
```bash
slackcli conversations list --types public_channel,private_channel | grep -i "<search_term>"
```

### Find users:
```bash
slackcli users list --json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for u in data:
    name = str(u.get('name', '') or '') + ' ' + str(u.get('real_name', '') or '')
    if '<search_term>' in name.lower():
        print(f\"ID: {u.get('id')}  |  @{u.get('name')}  |  {u.get('real_name', '')}\")
"
```

Present results in a clean formatted list.

## Step 4f: Auth Management

| Command | Description |
|---|---|
| `slackcli auth list` | Show all configured workspaces |
| `slackcli auth login --token "<TOKEN>" --workspace-name "<NAME>"` | Add a new workspace |
| `slackcli auth set-default --workspace-name "<NAME>"` | Switch default workspace |
| `slackcli auth remove --workspace-name "<NAME>"` | Remove a workspace |

If the user wants to **add a new workspace** and doesn't have a token, walk them through the full setup guide from Step 1.3.

## Step 5: Confirm & Report

After every action:
- **send**: Confirm the message was delivered, show channel/user name
- **read**: Present messages in a clean, readable format
- **upload**: Show the file permalink from Slack
- **react**: Confirm the reaction was added
- **find**: Show formatted results
- **auth**: Show current workspace status

If any action fails, show the error and suggest fixes (e.g., missing scopes, expired token, wrong channel ID).

## Multi-Workspace Support

When the user has multiple workspaces:
- Check which workspace is the default with `slackcli auth list`
- Use `--workspace "<NAME>"` flag on commands to target a specific workspace
- If the action target is ambiguous across workspaces, ask the user which workspace to use
