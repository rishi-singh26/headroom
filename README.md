# Headroom

Track your Claude Code usage from the terminal. Get push notifications when you're running low.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/rishi-singh26/headroom/refs/heads/main/docs/clhead-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/rishi-singh26/headroom/refs/heads/main/docs/clhead.png">
  <img alt="iOS" src="https://raw.githubusercontent.com/rishi-singh26/headroom/refs/heads/main/docs/clhead.png">
</picture>

## What it does

- Shows session (5h), weekly (7d), and context window usage with progress bars
- Displays reset countdowns and current session cost
- Optionally sends push notifications via [brrr.now](https://brrr.now) at 80% and 90% usage thresholds
- Optionally sends push notifications for every Claude Code hook event (session start/stop, tool use, prompts, etc.)

## Requirements

- Claude Code CLI
- Python 3
- `curl` (for push notifications)

## Compatibility

Works on macOS (zsh) and Linux (bash). The setup script detects your shell automatically and adds aliases to the correct rc file (`~/.zshrc` or `~/.bashrc`). All generated scripts use `#!/usr/bin/env bash` and are compatible with both platforms.

## Setup

```bash
bash headroom-setup.sh
```

The script is interactive — it will prompt for an optional brrr.now secret at the end. **Press Enter to skip** if you don't want push notifications.

To run non-interactively (no notifications):

```bash
echo "" | bash headroom-setup.sh
```

The script is safe to re-run. Each step checks before writing, so running it again on an already-configured system is a no-op.

## Usage

After setup, reload your shell:

```bash
source ~/.bashrc   # or ~/.zshrc
```

Then:

```bash
clhead             # show usage once
clhead-watch       # refresh every 5 minutes
clhead-watch 2     # refresh every 2 minutes
```

Example output:

```
  Session (5h)  [####################]  100%  resets in 3h 12m (Fri 14:30)
  Week (7d)     [########............]   42%  resets in 4d
  Context       [####................]   18%

  ────────────────────────────────────────────
  Model         Claude Sonnet 4.6
  Session cost  $1.23
  Updated       11:18
```

---

## What the setup script does

### Step 1 — Create `~/.claude/headroom/`

All headroom files live here.

### Step 2 — Write `statusline.sh`

A hook script that Claude Code calls after every prompt. It receives a JSON payload from Claude Code on stdin and saves it to `headroom-usage.json`. If brrr.now is configured, it also launches `notify.sh` in the background.

### Step 3 — Patch `~/.claude/settings.json`

Wires `statusline.sh` as the Claude Code `statusLine` hook. Uses Python to read and merge the existing settings file so no existing keys are lost. Creates the file if it doesn't exist.

### Step 4 — Write `headroom.sh`

The terminal display script. Reads `headroom-usage.json` and renders usage bars, percentages, reset countdowns, model name, and session cost.

### Step 5 — Add shell aliases

Adds `clhead` and `clhead-watch` to your `~/.bashrc` or `~/.zshrc`.

### Step 6–10 — brrr.now setup (optional)

If you provide a brrr.now secret, the script also:

- Writes `config.json` with your secret (mode 600)
- Writes `notify.sh` — a threshold notifier that alerts at 80% and 90% usage
- Writes `hook-notify.sh` — sends a push notification for every Claude Code hook event
- Wires `hook-notify.sh` into all Claude Code hook event types in `settings.json`
- Updates `statusline.sh` to launch `notify.sh` in the background after each prompt

---

## Generated files

| File | Purpose |
|------|---------|
| `statusline.sh` | Claude Code hook — saves usage JSON, triggers `notify.sh` |
| `headroom.sh` | Terminal display script (`clhead`) |
| `notify.sh` | Background notifier — sends alerts at 80% and 90% thresholds |
| `hook-notify.sh` | Sends a push notification for each Claude Code hook event |
| `config.json` | Stores your brrr.now secret (mode 600) |
| `headroom-usage.json` | Latest usage data from Claude Code (written after each prompt) |
| `.notify-state` | Tracks which threshold alerts have been sent (prevents duplicates) |
| `notify.log` | Log of threshold alert sends |
| `hook-notify.log` | Log of hook event notification sends |

---

## Push notifications (brrr.now)

[brrr.now](https://brrr.now) is a simple push notification service. Get the app, find your secret (looks like `br_usr_...`), and paste it during setup.

**Threshold notifications** — `notify.sh` runs after every prompt and checks your session and weekly usage:

- At 80%: sends one alert, resets when usage drops below 80%
- At 90%: sends one alert, resets when usage drops below 90%
- Below 80%: clears both flags so alerts will fire again next time

**Hook event notifications** — `hook-notify.sh` fires on every Claude Code event: session start/stop, each prompt you submit, every tool call, task completions, context compaction, and more.

### Skipping brrr.now

Just press **Enter** when the setup script asks for your secret. Steps 6–10 are skipped entirely. You still get the terminal display (`clhead`) and usage tracking — just no push notifications.

To add notifications later, re-run `bash headroom-setup.sh` and enter your secret when prompted.

---

## Data flow

```
Claude Code
    │
    ▼
statusline.sh          ← runs after every prompt
    │
    ├──▶ headroom-usage.json
    │         │
    │         └──▶ headroom.sh (clhead)     ← you read this
    │
    └──▶ notify.sh (background)             ← sends threshold alerts
```

Hook events follow a separate path: Claude Code fires `hook-notify.sh` directly for each event type wired in `settings.json`.
