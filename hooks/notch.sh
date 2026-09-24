#!/bin/bash
# notch.sh — one Claude Code hook, six states.
#
#   usage: notch.sh <state>    state = idle|working|needs_you|done|idle_done|gone
#
# Claude Code runs this with the hook's JSON payload on stdin. It writes one
# small file per session to ~/.claude-notch/sessions/<session_id>.json (state,
# where it runs, and the session's name read from its transcript), which
# the Lightswitch app watches; `gone` deletes it. Nothing is ever printed to
# stdout (Claude Code parses hook stdout as JSON) and the exit status is
# always 0, so a broken script can never block a session.
#
# jq is used when present. Without it, plutil (always on macOS) parses the
# payload and printf writes the file, so there are no dependencies.
# NOTCH_NO_JQ=1 forces the plutil path (used by the tests).

exec >/dev/null

state="$1"
input=$(cat)

case "$state" in
    idle|working|needs_you|done|idle_done|gone) ;;
    *) exit 0 ;;
esac

# --- JSON reading ------------------------------------------------------------

jq_bin=""
if [ -z "$NOTCH_NO_JQ" ]; then
    for c in "$(command -v jq 2>/dev/null)" /usr/bin/jq /opt/homebrew/bin/jq; do
        if [ -n "$c" ] && [ -x "$c" ]; then
            jq_bin="$c"
            break
        fi
    done
fi

# jsonfield <key> <json>: a top-level scalar from a JSON text, or empty.
jsonfield() {
    if [ -n "$jq_bin" ]; then
        printf '%s' "$2" | "$jq_bin" -r --arg k "$1" '.[$k] | select(. != null)' 2>/dev/null
    else
        printf '%s' "$2" | plutil -extract "$1" raw -o - - 2>/dev/null
    fi
}

# field <key>: the same, from the hook payload.
field() {
    jsonfield "$1" "$input"
}

# filefield <key> <file>: the same, from an existing session file.
filefield() {
    if [ -n "$jq_bin" ]; then
        "$jq_bin" -r --arg k "$1" '.[$k] | select(. != null)' "$2" 2>/dev/null
    else
        plutil -extract "$1" raw -o - "$2" 2>/dev/null
    fi
}

sid=$(field session_id)
[ -z "$sid" ] && exit 0
case "$sid" in */*|.*) exit 0 ;; esac   # it becomes a file name

dir="$HOME/.claude-notch/sessions"
f="$dir/$sid.json"

if [ "$state" = "gone" ]; then
    rm -f "$f" "$f.tmp"
    exit 0
fi

mkdir -p "$dir" 2>/dev/null || exit 0

cwd=$(field cwd)
[ -z "$cwd" ] && cwd="${CLAUDE_PROJECT_DIR:-$PWD}"

idle=false
if [ "$state" = "idle_done" ]; then
    state=done
    idle=true
fi

# --- the session's name ------------------------------------------------------
# Claude Code keeps a session's name in its transcript, not in the payload:
# a `custom-title` line from /rename (the last one wins; an empty one means
# the name was cleared), else the `ai-title` it generates from the
# conversation. Both are one-line JSON records, so the last match is the
# current one.

title=""
transcript=$(field transcript_path)
if [ -n "$transcript" ] && [ -r "$transcript" ]; then
    line=$(grep -a '"type":"custom-title"' "$transcript" 2>/dev/null | tail -n 1)
    [ -n "$line" ] && title=$(jsonfield customTitle "$line")
    if [ -z "$title" ]; then
        line=$(grep -a '"type":"ai-title"' "$transcript" 2>/dev/null | tail -n 1)
        [ -n "$line" ] && title=$(jsonfield aiTitle "$line")
    fi
    title=$(printf '%s' "$title" | tr -d '\000-\037')
fi

# Skip the write when nothing changed. idle_done always writes (it refreshes
# the timestamp the app pulses on); a plain done after it clears the flag.
# A new name is a change: the title arrives a moment after the first prompt.
if [ "$idle" = false ] && [ -f "$f" ]; then
    cur_state=$(filefield state "$f")
    cur_idle=$(filefield idle "$f")
    cur_title=$(filefield title "$f")
    [ "$cur_state" = "$state" ] && [ "$cur_idle" = "false" ] && [ "$cur_title" = "$title" ] && exit 0
fi

# --- which process is the session --------------------------------------------
# Hooks run under bash, which usually execs this script straight from the
# claude process, but not always. Walk up a few parents looking for it.

pid=$PPID
p=$PPID
i=0
while [ $i -lt 6 ] && [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
    line=$(ps -o ppid=,comm= -p "$p" 2>/dev/null)
    [ -z "$line" ] && break
    set -- $line
    ppid=$1
    shift
    comm=$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]')
    case "$comm" in
        *claude*) pid=$p; break ;;
    esac
    p=$ppid
    i=$((i + 1))
done
case "$pid" in ''|*[!0-9]*) pid=0 ;; esac

tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
[ "$tty" = "??" ] && tty=""
term="${TERM_PROGRAM:-}"
ts=$(date +%s)

# --- write -------------------------------------------------------------------

if [ -n "$jq_bin" ]; then
    "$jq_bin" -n --arg sid "$sid" --arg state "$state" --arg cwd "$cwd" \
        --argjson pid "$pid" --arg tty "$tty" --arg term "$term" \
        --argjson idle "$idle" --argjson ts "$ts" --arg title "$title" \
        '{session_id:$sid,state:$state,cwd:$cwd,pid:$pid,tty:$tty,term_program:$term,idle:$idle,updated_at:$ts,title:$title}' \
        > "$f.tmp" 2>/dev/null
else
    esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
    printf '{"session_id":"%s","state":"%s","cwd":"%s","pid":%s,"tty":"%s","term_program":"%s","idle":%s,"updated_at":%s,"title":"%s"}\n' \
        "$(esc "$sid")" "$state" "$(esc "$cwd")" "$pid" "$(esc "$tty")" "$(esc "$term")" "$idle" "$ts" "$(esc "$title")" \
        > "$f.tmp" 2>/dev/null
fi

if [ -s "$f.tmp" ]; then
    mv -f "$f.tmp" "$f" 2>/dev/null
else
    rm -f "$f.tmp"
fi
exit 0
