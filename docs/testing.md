# Testing checklist

The plan's pass conditions, with the date each last passed and how. "Unit"
means `swift test` (the C suite is `make test`); "snapshot" means the app's
offscreen render (`LIGHTSWITCH_SNAPSHOT_DIR` + `kill -USR1`) was inspected;
"manual" means someone has to be at the Mac. Re-run the table after a change
to the notch layout, the hook script, or a Claude Code update.

| Phase | Check | Pass when | Last passed | How |
| --- | --- | --- | --- | --- |
| 1 | Hover the notch, move away, repeat 10 times | Opens after 0.3 s, closes on mouse-out, no flicker | pending | manual (the screen was locked during the build; hover events could not reach the window) |
| 1 | Plug in an external display | A pill appears at menu-bar height, dots centred in it | pending | manual |
| 1 | Open a fullscreen app | The notch still floats above it | pending | manual (private space resolved and applied, `PrivateSpace.available == true`) |
| 1 | Closed shape covers the physical notch exactly | Shape width = notch + 4, window centred on the notch, not the screen | 2026-09-24 | unit (`NotchGeometryTests`) + snapshot |
| 2 | Write, edit, delete session files by hand (`pid: 1`) | Dot appears or changes within 100 ms; deleting removes it; slots keep order when a middle session leaves | 2026-09-24 | unit (`SessionStoreTests`) + snapshot |
| 2 | Write a file with a dead `pid` | Dot disappears within 10 s | 2026-09-24 | unit (`testPruneRemovesDeadProcessesAndKeepsLiveOnes`) |
| 2 | Five sessions | Four dots and "+1" in the notch; all five in the open list, duplicate folders show a short id | 2026-09-24 | snapshot |
| 3 | Hook script: each state, unchanged-state skip, `idle_done`, `gone`, no stdout, exit 0, with and without jq | Files match the format exactly | 2026-09-24 | unit (`HookInstallerTests`, runs the real script through bash) |
| 3 | Install into an empty, an unrelated, and an already-installed `settings.json`; uninstall; invalid JSON | Only `notch.sh` entries added or removed; every other key survives; invalid JSON refused, original unchanged, no backup written | 2026-09-24 | unit |
| 3 | Four real `claude` sessions; one permission prompt; one `/exit`; one `kill -9` | Colours follow the state machine; `/exit` removes the dot at once; `kill -9` within 10 s | pending | manual (hooks were deliberately not installed into the real `~/.claude/settings.json` during the build) |
| 3 | `$PPID` in a real hook resolves to the `claude` process | `pid` in the session file is the claude process | pending | manual; the script walks up to six parents looking for "claude" |
| 4 | A session turns red while the notch is closed | Peek beside the notch for 3 s, sound once, dot pulses until acknowledged | 2026-09-24 | snapshot (sound path is `NSSound(named: "Glass")`, exercised with sound off) |
| 4 | `idle_prompt` (`done` with `idle: true`) | Green dot breathes slowly, no sound | 2026-09-24 | snapshot |
| 5 | Replay fixtures through the sensor engine in switch mode | `hold`/`tap` → cover, uncover; `idle`/`walk_past`/`drift` → nothing; `dark` → fault | 2026-09-24 | unit (`SensorEngineTests`) |
| 5 | Cup a hand over the notch in a lit room | Fires once per cover, re-arms on uncover; refuses under 25 lux with a message in Settings | pending | manual (the display was asleep: both the app and the C CLI reported "no ambient light sensor found"; the app retries every 30 s and on wake) |
| 6 | Click a red dot / row with VS Code, iTerm, Terminal sessions | The right tab comes forward (iTerm, Terminal); the folder's window comes forward (VS Code) | pending | manual (needs the Automation permission prompt) |
| 6 | Menu bar: Launch at Login | Registered as a login item from the bundled app | pending | manual |

## Manual soak

Run the bundled app for a full working day with hooks installed before
calling Phase 3 done. Watch for a stale dot from a session that died without
`SessionEnd` (should vanish within 10 s) and for hooks launched from a GUI app
where `jq` is not on `PATH` (the script falls back to `plutil`, so this should
be invisible).

## Driving the app without Claude Code

```bash
mkdir -p /tmp/sessions
LIGHTSWITCH_SESSIONS_DIR=/tmp/sessions LIGHTSWITCH_SNAPSHOT_DIR=/tmp/snaps .build/debug/Lightswitch &
printf '{"session_id":"a","state":"needs_you","cwd":"/tmp/x","pid":1,"tty":"","term_program":"","idle":false,"updated_at":0}' > /tmp/sessions/a.json
kill -USR2 $(pgrep -x Lightswitch)   # toggle the notch open
kill -USR1 $(pgrep -x Lightswitch)   # write PNGs of every notch window to /tmp/snaps
```
