#!/usr/bin/env bash
# headroom-setup.sh — one-command setup for Claude Code usage tracking
#
# What this does:
#   1. Creates ~/.claude/headroom/               (all headroom files live here)
#   2. Creates ~/.claude/headroom/statusline.sh  (hook Claude Code runs after each prompt)
#   3. Patches ~/.claude/settings.json           (wires the hook into Claude Code)
#   4. Creates ~/.claude/headroom/headroom.sh    (terminal display script)
#   5. Adds clhead / clhead-watch aliases to shell rc file
#   6. Asks for brrr.now secret
#   7. Creates ~/.claude/headroom/config.json    (stores secret)
#   8. Creates ~/.claude/headroom/notify.sh      (background usage threshold notifier)
#   9. Creates ~/.claude/headroom/hook-notify.sh (Claude Code hook event notifier)
#  10. Updates settings.json with hook-notify.sh hooks
#  11. Rewrites statusline.sh to also launch notify.sh

set -e

CLAUDE_DIR="${HOME}/.claude"
HEADROOM_DIR="${CLAUDE_DIR}/headroom"
HOOK_SCRIPT="${HEADROOM_DIR}/statusline.sh"
USAGE_JSON="${HEADROOM_DIR}/headroom-usage.json"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
DISPLAY_SCRIPT="${HEADROOM_DIR}/headroom.sh"
NOTIFY_SCRIPT="${HEADROOM_DIR}/notify.sh"
HOOK_NOTIFY_SCRIPT="${HEADROOM_DIR}/hook-notify.sh"
CONFIG_FILE="${HEADROOM_DIR}/config.json"

# ── colours ────────────────────────────────────────────────────────────────────
GREEN=$'\e[32m'
GRAY=$'\e[90m'
BOLD=$'\e[1m'
RESET=$'\e[0m'
YELLOW=$'\e[33m'

step()  { printf '\n%s==>%s %s%s%s\n' "$GREEN" "$RESET" "$BOLD" "$*" "$RESET"; }
info()  { printf '    %s%s%s\n' "$GRAY" "$*" "$RESET"; }
warn()  { printf '    %s%s%s\n' "$YELLOW" "$*" "$RESET"; }
done_() { printf '    %s%s%s\n' "$GREEN" "$*" "$RESET"; }

# ── detect shell rc file ───────────────────────────────────────────────────────
detect_rc() {
    if [[ -n "$ZSH_VERSION" ]] || [[ "$SHELL" == */zsh ]]; then
        echo "${HOME}/.zshrc"
    elif [[ -n "$BASH_VERSION" ]] || [[ "$SHELL" == */bash ]]; then
        echo "${HOME}/.bashrc"
    elif [[ -f "${HOME}/.zshrc" ]]; then
        echo "${HOME}/.zshrc"
    else
        echo "${HOME}/.bashrc"
    fi
}
RC_FILE=$(detect_rc)

# ══════════════════════════════════════════════════════════════════════════════
# PART 1 — CORE SETUP
# ══════════════════════════════════════════════════════════════════════════════

# ── 1. Create ~/.claude/headroom ──────────────────────────────────────────────
step "Creating ~/.claude/headroom directory"
mkdir -p "$HEADROOM_DIR"
done_ "$HEADROOM_DIR"

# ── 2. Write statusline.sh (initial — no notify.sh yet) ───────────────────────
step "Writing hook script -> $HOOK_SCRIPT"
cat > "$HOOK_SCRIPT" << 'HOOK_END'
#!/bin/bash
# statusline.sh — Claude Code statusLine hook
# Saves Claude Code's session JSON to ~/.claude/headroom/headroom-usage.json
input=$(cat)
printf '%s' "$input" > "$HOME/.claude/headroom/headroom-usage.json"
HOOK_END
chmod +x "$HOOK_SCRIPT"
done_ "Hook script written"

# ── 3. Patch settings.json ────────────────────────────────────────────────────
step "Patching Claude Code settings -> $SETTINGS_FILE"
if [[ -f "$SETTINGS_FILE" ]]; then
    if grep -q "headroom/statusline.sh" "$SETTINGS_FILE" 2>/dev/null; then
        info "Already wired — skipping settings patch"
    else
        cp "$SETTINGS_FILE" "${SETTINGS_FILE}.bak"
        info "Backed up existing settings to settings.json.bak"
        python3 - "$SETTINGS_FILE" "$HOOK_SCRIPT" << 'PYEND'
import sys, json
settings_path, hook_path = sys.argv[1], sys.argv[2]
with open(settings_path) as f:
    settings = json.load(f)
settings["statusLine"] = {"type": "command", "command": hook_path}
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2); f.write("\n")
PYEND
        done_ "settings.json updated"
    fi
else
    python3 - "$SETTINGS_FILE" "$HOOK_SCRIPT" << 'PYEND'
import sys, json
settings_path, hook_path = sys.argv[1], sys.argv[2]
settings = {"statusLine": {"type": "command", "command": hook_path}}
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2); f.write("\n")
PYEND
    done_ "settings.json created"
fi

# ── 4. Write headroom.sh ──────────────────────────────────────────────────────
step "Writing display script -> $DISPLAY_SCRIPT"
cat > "$DISPLAY_SCRIPT" << 'DISPLAY_END'
#!/usr/bin/env bash
# headroom.sh — print Claude Code usage from ~/.claude/headroom/headroom-usage.json
#
# Usage:
#   headroom.sh              show once
#   headroom.sh --watch [N]  refresh every N minutes (default 5), Ctrl-C to exit

JSON_FILE="${HOME}/.claude/headroom/headroom-usage.json"

show() {
    if [[ ! -f "$JSON_FILE" ]]; then
        echo "No data yet. Run a prompt in Claude Code first."
        return 1
    fi

    python3 - "$JSON_FILE" << 'EOF'
import sys, json, time, datetime, os

data = json.load(open(sys.argv[1]))

def get(obj, *keys):
    for k in keys:
        if isinstance(obj, dict) and k in obj:
            obj = obj[k]
        else:
            return None
    return obj

def countdown(ts):
    secs = int(ts) - int(time.time())
    if secs <= 0: return "now"
    d, rem = divmod(secs, 86400)
    h, rem = divmod(rem, 3600)
    m = rem // 60
    if d and h: return f"{d}d {h}h"
    if d:       return f"{d}d"
    if h and m: return f"{h}h {m}m"
    if h:       return f"{h}h"
    return f"{m}m"

def reset_label(ts):
    return datetime.datetime.fromtimestamp(int(ts)).strftime("%a %H:%M")

GREEN = "\033[32m"
RESET = "\033[0m"
BAR_WIDTH = 20

def bar(pct):
    filled = round(pct * BAR_WIDTH / 100)
    empty  = BAR_WIDTH - filled
    return f"{GREEN}{'#' * filled}{RESET}{'.' * empty}"

five_pct    = get(data, "rate_limits", "five_hour", "used_percentage")
five_reset  = get(data, "rate_limits", "five_hour", "resets_at")
seven_pct   = get(data, "rate_limits", "seven_day", "used_percentage")
seven_reset = get(data, "rate_limits", "seven_day", "resets_at")
ctx_pct     = get(data, "context_window", "used_percentage")
model       = get(data, "model", "display_name")
cost        = get(data, "cost",  "total_cost_usd")
mtime       = datetime.datetime.fromtimestamp(
                  os.path.getmtime(sys.argv[1])).strftime("%H:%M")

metric_rows = []
if five_pct is not None:
    note = f"resets in {countdown(five_reset)} ({reset_label(five_reset)})" if five_reset else ""
    metric_rows.append(("Session (5h)", five_pct, note))
if seven_pct is not None:
    note = f"resets in {countdown(seven_reset)} ({reset_label(seven_reset)})" if seven_reset else ""
    metric_rows.append(("Week (7d)", seven_pct, note))
if ctx_pct is not None:
    metric_rows.append(("Context", ctx_pct, ""))

info_rows = []
if model:
    info_rows.append(("Model",        model))
if cost is not None:
    info_rows.append(("Session cost", f"${cost:.2f}"))
info_rows.append(    ("Updated",      mtime))

all_labels = [r[0] for r in metric_rows] + [r[0] for r in info_rows]
w_label    = max(len(l) for l in all_labels)
w_pct      = 4
divider    = f"  {'─' * w_label}  {'─' * BAR_WIDTH}  {'─' * w_pct}  {'─' * 26}"

print()
for label, pct, note in metric_rows:
    pct_str = f"{pct:.0f}%"
    line = f"  {label:<{w_label}}  {bar(pct)}  {pct_str:>{w_pct}}"
    if note:
        line += f"  {note}"
    print(line)

print(divider)

for label, value in info_rows:
    print(f"  {label:<{w_label}}  {value}")
print()
EOF
}

if [[ "$1" == "--watch" ]]; then
    minutes="${2:-5}"
    interval=$(( minutes * 60 ))
    while true; do
        clear
        show
        printf '  \033[90mRefreshing in %s minute(s) — Ctrl-C to exit\033[0m\n' "$minutes"
        sleep "$interval"
    done
else
    show
fi
DISPLAY_END
chmod +x "$DISPLAY_SCRIPT"
done_ "Display script written"

# ── 5. Add aliases ────────────────────────────────────────────────────────────
step "Adding aliases to $RC_FILE"
ALIAS_ONCE="alias clhead='${DISPLAY_SCRIPT}'"
ALIAS_WATCH="alias clhead-watch='${DISPLAY_SCRIPT} --watch'"
if grep -qF "alias clhead=" "$RC_FILE" 2>/dev/null; then
    info "alias clhead already exists — skipping"
else
    printf '\n# Headroom — Claude Code usage\n%s\n%s\n' "$ALIAS_ONCE" "$ALIAS_WATCH" >> "$RC_FILE"
    done_ "Aliases added to $RC_FILE"
fi

# ══════════════════════════════════════════════════════════════════════════════
# PART 2 — NOTIFICATIONS (brrr.now)
# ══════════════════════════════════════════════════════════════════════════════
printf '\n%s────────────────────────────────────────%s\n' "$GRAY" "$RESET"
printf '%sCore setup complete. Now configuring push notifications.%s\n' "$BOLD" "$RESET"
printf '%s────────────────────────────────────────%s\n' "$GRAY" "$RESET"

step "Configuring brrr.now push notifications"
printf '\n'
printf '  Enter your brrr.now secret.\n'
printf '  Find it in the brrr app — looks like: %sbr_usr_...%s\n' "$GRAY" "$RESET"
printf '  Leave blank to skip.\n\n'
printf '  Secret: '
read -r BRRR_SECRET

if [[ -z "$BRRR_SECRET" ]]; then
    warn "Skipped — re-run this script any time to add notifications"
else
    if [[ "$BRRR_SECRET" != br_* ]]; then
        warn "Secret doesn't look right (expected br_...) — saving anyway"
    fi

    # ── 6. Write config.json ──────────────────────────────────────────────────
    python3 - "$CONFIG_FILE" "$BRRR_SECRET" << 'PYEND'
import sys, json
config_path, raw = sys.argv[1], sys.argv[2].strip()
if raw.startswith("http"):
    raw = raw.rstrip("/").split("/")[-1]
with open(config_path, "w") as f:
    json.dump({"brrr_secret": raw}, f, indent=2); f.write("\n")
PYEND
    chmod 600 "$CONFIG_FILE"
    done_ "Config written to $CONFIG_FILE (mode 600)"

    # ── 7. Write notify.sh ────────────────────────────────────────────────────
    step "Writing usage threshold notifier -> $NOTIFY_SCRIPT"
    cat > "$NOTIFY_SCRIPT" << 'NOTIFY_END'
#!/bin/bash
# notify.sh — headroom background notification checker
# Reads headroom-usage.json and sends brrr.now alerts at 80% and 90% thresholds.
#
# Threshold logic (session and week tracked independently):
#   < 80%    — clear both flags (full reset)
#   80%-89%  — send 80% alert if not sent; clear 90% flag
#   >= 90%   — send 90% alert if not sent

HEADROOM_DIR="$HOME/.claude/headroom"
USAGE_JSON="$HEADROOM_DIR/headroom-usage.json"
STATE_FILE="$HEADROOM_DIR/.notify-state"
CONFIG_FILE="$HEADROOM_DIR/config.json"
LOCK_FILE="$HEADROOM_DIR/.notify.lock.d"
LOG_FILE="$HEADROOM_DIR/notify.log"
T80=80
T90=90

log() {
    local ts; ts=$(date "+%Y-%m-%d %H:%M:%S")
    local line="$ts  $1"
    if [[ -f "$LOG_FILE" ]]; then
        local tmp; tmp=$(tail -n 99 "$LOG_FILE")
        printf "%s\n%s\n" "$tmp" "$line" > "$LOG_FILE"
    else
        printf "%s\n" "$line" > "$LOG_FILE"
    fi
}

if ! mkdir "$LOCK_FILE" 2>/dev/null; then exit 0; fi
trap 'rm -rf "$LOCK_FILE"' EXIT

if [[ ! -f "$CONFIG_FILE" ]]; then log "config.json not found"; exit 0; fi

raw_secret=$(python3 -c "
import json
try:
    d = json.load(open('$CONFIG_FILE'))
    v = d.get('brrr_secret','').strip()
    if v.startswith('http'): v = v.rstrip('/').split('/')[-1]
    print(v)
except Exception: print('')
" 2>/dev/null)
if [[ -z "$raw_secret" ]]; then log "brrr_secret empty"; exit 0; fi
secret="$raw_secret"

if [[ ! -f "$USAGE_JSON" ]]; then log "headroom-usage.json not found"; exit 0; fi

five_pct=$(python3 -c "
import json
try:
    d = json.load(open('$USAGE_JSON'))
    v = d.get('rate_limits',{}).get('five_hour',{}).get('used_percentage')
    print('' if v is None else int(v))
except Exception: print('')
" 2>/dev/null)

seven_pct=$(python3 -c "
import json
try:
    d = json.load(open('$USAGE_JSON'))
    v = d.get('rate_limits',{}).get('seven_day',{}).get('used_percentage')
    print('' if v is None else int(v))
except Exception: print('')
" 2>/dev/null)

if [[ -z "$five_pct" && -z "$seven_pct" ]]; then log "No rate limit data"; exit 0; fi

state_get() {
    local key="$1"
    [[ -f "$STATE_FILE" ]] && grep -m1 "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2
}

state_set() {
    local key="$1" val="$2" tmp="${STATE_FILE}.tmp"
    if [[ -f "$STATE_FILE" ]]; then
        grep -v "^${key}=" "$STATE_FILE" > "$tmp" 2>/dev/null || true
    else
        : > "$tmp"
    fi
    printf "%s=%s\n" "$key" "$val" >> "$tmp"
    mv "$tmp" "$STATE_FILE"
}

send_notification() {
    local title="$1" message="$2"
    local payload
    payload=$(python3 -c "
import json, sys
print(json.dumps({
    'title': sys.argv[1], 'message': sys.argv[2],
    'sound': 'upbeat_bells', 'interruption_level': 'time-sensitive',
}))" "$title" "$message")
    [[ -z "$payload" ]] && { log "Failed to build payload"; return 1; }
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 -X POST "https://api.brrr.now/v1/${secret}" \
        -H "Content-Type: application/json" -d "$payload" 2>/dev/null)
    if [[ "$http_code" =~ ^2 ]]; then
        log "OK ($http_code): $title"; return 0
    else
        log "Failed ($http_code): $title"; return 1
    fi
}

check_window() {
    local window="$1" pct="$2" label="$3"
    local k80="${window}_sent80" k90="${window}_sent90"
    local sent80; sent80=$(state_get "$k80")
    local sent90; sent90=$(state_get "$k90")
    if (( pct < T80 )); then
        if [[ "$sent80" == "1" || "$sent90" == "1" ]]; then
            log "$label below ${T80}% (${pct}%) — resetting"
        fi
        state_set "$k80" "0"; state_set "$k90" "0"
    elif (( pct < T90 )); then
        if [[ "$sent90" == "1" ]]; then
            log "$label below ${T90}% (${pct}%) — resetting 90% flag"
        fi
        state_set "$k90" "0"
        if [[ "$sent80" != "1" ]]; then
            if send_notification "Claude Code $label at ${pct}%" \
                "You have used ${pct}% of your $label quota."; then
                state_set "$k80" "1"
            fi
        fi
    else
        if [[ "$sent90" != "1" ]]; then
            if send_notification "Warning: Claude Code $label at ${pct}%" \
                "Critical: ${pct}% of your $label quota used."; then
                state_set "$k90" "1"
            fi
        fi
    fi
}

[[ -n "$five_pct"  ]] && check_window "session" "$five_pct"  "Session (5h)"
[[ -n "$seven_pct" ]] && check_window "week"    "$seven_pct" "Week (7d)"
NOTIFY_END
    chmod +x "$NOTIFY_SCRIPT"
    done_ "Threshold notifier written"

    # ── 8. Write hook-notify.sh ───────────────────────────────────────────────
    step "Writing hook event notifier -> $HOOK_NOTIFY_SCRIPT"
    cat > "$HOOK_NOTIFY_SCRIPT" << 'HOOK_NOTIFY_END'
#!/bin/bash
# hook-notify.sh — Claude Code hook event -> brrr.now push notification
#
# Reads Claude Code's hook JSON from stdin, extracts context per event type,
# and sends a push notification. Always exits 0 — purely observational.

CONFIG_FILE="$HOME/.claude/headroom/config.json"
LOG_FILE="$HOME/.claude/headroom/hook-notify.log"

log() {
    local ts; ts=$(date "+%Y-%m-%d %H:%M:%S")
    local line="$ts  $1"
    if [[ -f "$LOG_FILE" ]]; then
        local tmp; tmp=$(tail -n 99 "$LOG_FILE")
        printf "%s\n%s\n" "$tmp" "$line" > "$LOG_FILE"
    else
        printf "%s\n" "$line" > "$LOG_FILE"
    fi
}

if [[ ! -f "$CONFIG_FILE" ]]; then exit 0; fi

secret=$(python3 -c "
import json
try:
    d = json.load(open('$CONFIG_FILE'))
    v = d.get('brrr_secret','').strip()
    if v.startswith('http'): v = v.rstrip('/').split('/')[-1]
    print(v)
except Exception: print('')
" 2>/dev/null)
if [[ -z "$secret" ]]; then exit 0; fi

INPUT=$(cat)
if [[ -z "$INPUT" ]]; then exit 0; fi

# Parse event and produce TAB-separated TITLE<TAB>MESSAGE via python3.
# The Python code is passed as a -c argument (no heredoc) to avoid the
# bash limitation of heredocs inside $(...) subshells.
PARSE_PY='
import sys, json, os

try:
    d = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

event     = d.get("hook_event_name", "")
cwd       = d.get("cwd", "")
tool_name = d.get("tool_name", "")

def short_cwd(p):
    home = os.path.expanduser("~")
    return p.replace(home, "~") if p.startswith(home) else p

def tool_summary():
    ti = d.get("tool_input", {})
    if tool_name == "Bash":
        cmd = ti.get("command", "")
        return cmd[:80] + ("..." if len(cmd) > 80 else "")
    if tool_name in ("Write", "Edit", "MultiEdit"):
        return ti.get("file_path", "")
    if tool_name == "Read":
        return ti.get("file_path", "")
    if tool_name == "WebFetch":
        return ti.get("url", "")
    if tool_name == "WebSearch":
        return ti.get("query", "")
    if tool_name == "TodoWrite":
        return f"{len(ti.get(\"todos\", []))} todo(s)"
    if tool_name.startswith("mcp__"):
        parts = tool_name.split("__")
        return (parts[1] if len(parts) > 1 else "") + " > " + (parts[2] if len(parts) > 2 else "")
    return tool_name

result = None
if event == "SessionStart":
    how = d.get("how", "")
    result = ("Claude Code - Session Started", short_cwd(cwd) + (f"  ({how})" if how else ""))
elif event == "SessionEnd":
    why = d.get("why", "")
    result = ("Claude Code - Session Ended", short_cwd(cwd) + (f"  ({why})" if why else ""))
elif event == "UserPromptSubmit":
    prompt = d.get("prompt", "")
    result = ("Claude Code - Prompt Submitted", prompt[:100] + ("..." if len(prompt) > 100 else ""))
elif event == "PreToolUse":
    result = (f"Claude Code - {tool_name} (before)", tool_summary())
elif event == "PostToolUse":
    result = (f"Claude Code - {tool_name} (done)", tool_summary())
elif event == "PostToolUseFailure":
    err = d.get("tool_response", {})
    if isinstance(err, dict): err = err.get("error", str(err))
    result = (f"Claude Code - {tool_name} failed", (tool_summary() + "  " + str(err)[:80]).strip())
elif event == "Stop":
    stop_reason = d.get("stop_reason", "")
    result = ("Claude Code - Done", stop_reason if stop_reason else short_cwd(cwd))
elif event == "Notification":
    nt = d.get("title", "")
    nm = d.get("message", "")
    result = (f"Claude Code - {nt}" if nt else "Claude Code Notification", nm[:120])
elif event == "SubagentStart":
    result = ("Claude Code - Subagent Started", d.get("agent_type", "") or "unknown")
elif event == "SubagentStop":
    result = ("Claude Code - Subagent Stopped", d.get("agent_type", "") or "unknown")
elif event == "PreCompact":
    result = ("Claude Code - Compacting Context", short_cwd(cwd))
elif event == "PostCompact":
    result = ("Claude Code - Context Compacted", short_cwd(cwd))
elif event == "StopFailure":
    result = ("Claude Code - Turn Failed", "Error: " + d.get("error_type", "unknown"))
elif event == "TaskCompleted":
    task = d.get("task", {})
    title = (task.get("title", "") if isinstance(task, dict) else str(task))[:100]
    result = ("Claude Code - Task Completed", title or short_cwd(cwd))
elif event == "ConfigChange":
    result = ("Claude Code - Config Changed", d.get("source", "") or short_cwd(cwd))

if result:
    print(result[0] + "\t" + result[1])
'

parsed=$(python3 -c "$PARSE_PY" "$INPUT" 2>/dev/null)
if [[ -z "$parsed" ]]; then exit 0; fi

TITLE="${parsed%%	*}"
MESSAGE="${parsed#*	}"
if [[ -z "$TITLE" ]]; then exit 0; fi

payload=$(python3 -c "
import json, sys
print(json.dumps({
    'title': sys.argv[1], 'message': sys.argv[2],
    'sound': 'upbeat_bells', 'interruption_level': 'active',
}))" "$TITLE" "$MESSAGE")

if [[ -z "$payload" ]]; then
    log "Failed to build payload for: $TITLE"
    exit 0
fi

http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    -X POST "https://api.brrr.now/v1/${secret}" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null)

if [[ "$http_code" =~ ^2 ]]; then
    log "OK ($http_code): $TITLE"
else
    log "Failed ($http_code): $TITLE"
fi
exit 0
HOOK_NOTIFY_END
    chmod +x "$HOOK_NOTIFY_SCRIPT"
    done_ "Hook event notifier written"

    # ── 9. Wire hook-notify.sh into settings.json ─────────────────────────────
    step "Wiring hook-notify.sh into Claude Code settings"
    python3 - "$SETTINGS_FILE" "$HOOK_NOTIFY_SCRIPT" << 'PYEND'
import sys, json

settings_path   = sys.argv[1]
hook_notify_path = sys.argv[2]

with open(settings_path) as f:
    settings = json.load(f)

hook_cmd = {"type": "command", "command": hook_notify_path}

# Events that use a matcher (tool events)
matcher_events = ["PreToolUse", "PostToolUse", "PostToolUseFailure"]
# Events that do not use a matcher
plain_events   = [
    "Stop", "StopFailure", "SessionStart", "SessionEnd",
    "Notification", "SubagentStart", "SubagentStop",
    "PreCompact", "PostCompact", "TaskCompleted", "ConfigChange",
    "UserPromptSubmit",
]

hooks = settings.setdefault("hooks", {})

for event in matcher_events:
    groups = hooks.setdefault(event, [])
    # Check if hook-notify is already wired for this event
    already = any(
        h.get("command") == hook_notify_path
        for g in groups
        for h in g.get("hooks", [])
    )
    if not already:
        groups.append({"matcher": "*", "hooks": [hook_cmd]})

for event in plain_events:
    groups = hooks.setdefault(event, [])
    already = any(
        h.get("command") == hook_notify_path
        for g in groups
        for h in g.get("hooks", [])
    )
    if not already:
        groups.append({"hooks": [hook_cmd]})

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2); f.write("\n")
PYEND
    done_ "Hook events wired in settings.json"

    # ── 10. Rewrite statusline.sh to also launch notify.sh ────────────────────
    step "Updating statusline.sh to launch notify.sh in background"
    cat > "$HOOK_SCRIPT" << 'HOOK_END'
#!/bin/bash
# statusline.sh — Claude Code statusLine hook
input=$(cat)
printf '%s' "$input" > "$HOME/.claude/headroom/headroom-usage.json"
bash "$HOME/.claude/headroom/notify.sh" >> "$HOME/.claude/headroom/notify.log" 2>&1 &
HOOK_END
    chmod +x "$HOOK_SCRIPT"
    done_ "statusline.sh updated"

fi  # end brrr.now block

# ── summary ────────────────────────────────────────────────────────────────────
printf '\n%s════════════════════════════════════════%s\n' "$GRAY" "$RESET"
printf '%sAll done!%s\n\n' "$BOLD" "$RESET"
printf '  Directory:    %s\n' "$HEADROOM_DIR"
printf '  Hook:         %s\n' "$HOOK_SCRIPT"
printf '  Display:      %s\n' "$DISPLAY_SCRIPT"
printf '  Settings:     %s\n' "$SETTINGS_FILE"
if [[ -f "$NOTIFY_SCRIPT" ]]; then
    printf '  Notifier:     %s\n' "$NOTIFY_SCRIPT"
    printf '  Hook notify:  %s\n' "$HOOK_NOTIFY_SCRIPT"
    printf '  Config:       %s\n' "$CONFIG_FILE"
    printf '  Notify log:   %s\n' "${HEADROOM_DIR}/notify.log"
    printf '  Hook log:     %s\n' "${HEADROOM_DIR}/hook-notify.log"
fi
printf '\n%sAliases:%s\n' "$BOLD" "$RESET"
printf '  clhead              show usage once\n'
printf '  clhead-watch [N]    refresh every N minutes (default 5)\n'
printf '\n%sNext steps:%s\n' "$BOLD" "$RESET"
printf '  1. Reload your shell:  source %s\n' "$RC_FILE"
printf '  2. Run a prompt in Claude Code to populate the data\n'
printf '  3. Then run:           clhead\n'
printf '%s════════════════════════════════════════%s\n\n' "$GRAY" "$RESET"