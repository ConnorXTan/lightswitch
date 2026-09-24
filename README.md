# lightswitch

Turns the MacBook notch into a status light for Claude Code, and the ambient
light sensor behind it into a button.

Run the app and one dot per running Claude Code session appears in a black island around the
notch: yellow while Claude works, red when it is waiting on you, green when it
is done. Hover to see the list; click a dot to jump to that terminal. Cup your
hand over the notch and the session that needs you comes to the front. The
notch never had a job before; now it has one.

Under it is the original tool: a full gesture engine over a sensor with no
public API, one bit of usable signal, and a refresh rate of 4.7 Hz. Run
`lightswitch` bare and the notch is a music switch; bind a **tap**,
**double-tap** or **hold** to any keystroke, shell command or media key.

## The app

```
make app && open build/Lightswitch.app
```

Then **Install hooks** from the menu bar icon, or from the empty notch. That
adds eight hook entries (six events) to `~/.claude/settings.json` (backed up to
`settings.json.bak` first, nothing else touched), each running
`~/.claude/hooks/notch.sh`. From then on every Claude Code session writes one
small JSON file to `~/.claude-notch/sessions/` as it changes state, and the
app watches that folder. Sessions run exactly the same with the app closed;
state lives in files it only reads.

| Dot | Meaning | Written by |
| --- | --- | --- |
| grey | idle: session started, nothing asked yet | `SessionStart` |
| yellow | working | `UserPromptSubmit`, `PostToolUse` |
| red, pulsing | needs you: a permission prompt or a question | `Notification` (`permission_prompt`, `elicitation_dialog`) |
| green | done, waiting for your next message | `Stop` |
| green, breathing | done and Claude has been waiting a while | `Notification` (`idle_prompt`) |

`PostToolUse` is the transition people forget: after you approve a permission
prompt no `UserPromptSubmit` fires, so without it the dot would stay red while
Claude is working again. `SessionEnd` deletes the file; sessions that die
without it (`kill -9`, a closed terminal window) are pruned when their process
is gone.

Hover the notch and it opens into a list grouped by repository: the repo as a
header, and under it each Claude terminal ("VS Code · ttys004") with the
subfolder or worktree it sits in, its state and how long ago it changed. A
session in a linked worktree (Claude Code's `.claude/worktrees/<name>`, or one
kept elsewhere) lists under the repository it belongs to. Two projects with
the same folder name show where they live.

When a session turns red the notch widens for three seconds to say which
folder and plays a sound (Settings turns it off). The dot keeps pulsing until
you click it, cover the notch, or the state changes.

**The gesture.** With the sensor on (Settings → Light sensor), covering the
notch does one thing, your choice: jump to the session that needs you (else
open the notch), just open the notch, acknowledge the red dots, play/pause the
music, or the original ⌘W. It fires about 300 ms after your hand arrives,
which is the hardware floor; see [docs/SIGNAL.md](docs/SIGNAL.md). Turn off
**Displays → Automatically adjust brightness** or macOS dims the screen as you
shade the sensor.

**Terminals.** Clicking a session brings its terminal forward: the exact tab
in iTerm and Terminal (via AppleScript, which asks for Automation permission
once), the folder's window in VS Code and Cursor, the app for Ghostty, kitty,
WezTerm, Warp and the rest.

The app is a menu-bar accessory for macOS 14 or newer, shown on every display
or just the built-in one. It is not sandboxed: the sensor is reached through
private IOKit HID calls that the sandbox blocks.

### Developing the app

```
swift build            debug binary in .build/debug/Lightswitch
swift test             the Swift suite (session store, hook installer, sensor bridge, terminal focus)
open Package.swift     the same targets in Xcode
make app               release build wrapped as build/Lightswitch.app, icon included
```

Two environment variables make the app drivable from a terminal:
`LIGHTSWITCH_SESSIONS_DIR` points it at a folder of hand-written session
files, and with `LIGHTSWITCH_SNAPSHOT_DIR` set, `kill -USR1` writes a PNG of
every notch window there (`kill -USR2` toggles the notch open). Both are how
the layouts in this README were checked; the recipe is in
[docs/testing.md](docs/testing.md).

## The command-line tool

```console
$ lightswitch --on-hold key:cmd+w --on-double-tap 'exec:pmset displaysleepnow'
lightswitch 0.2.0 | source: iokit | actions ARMED
  tap        -> none
  double-tap -> exec:pmset displaysleepnow
  hold       -> key:cmd+w

calibrating for 2.0s — do not shade the screen...
baseline 6199 lux | cover below 2789 | release above 4649

Ready. Cup your hand over the top of the screen.

[   12.4s] hold        -> key:cmd+w
[   31.8s] double-tap  -> exec:pmset displaysleepnow
```

There is no public API for this sensor, no library, and one bit of usable
signal. Most of the work is in the part you cannot see: deciding what counts
as a gesture when the hardware updates only 4.7 times a second and the room
itself keeps changing brightness.

## Try it without a MacBook

The detector is platform-independent and the sensor is behind an interface, so
recorded traces replay through exactly the same code path as live hardware:

```console
$ make && make demo
Replaying recorded traces through the detector.
Each fixture is a scenario; the lines under it are what was recognised.

  idle
      (nothing — correctly ignored)
  walk_past
      (nothing — correctly ignored)
  drift
      (nothing — correctly ignored)
  dark
      lightswitch: ambient light too low (12 lux, need 25) — a shadow cannot
      be distinguished from the room
  office_session
      [    7.4s] tap
      [   25.1s] double-tap
      [   41.4s] hold
```

`walk_past` is someone crossing the room and `drift` is daylight fading over
five minutes; both dim the sensor substantially and neither is a gesture.

`make test` runs the full suite (304 assertions) on any Unix machine, sensor or
not. That is the point of the layering — see [Architecture](#architecture).

`--replay` selects the *source*, not a mode, so it composes with the rest:
`--monitor --replay FILE` watches a recording play back, and
`--calibrate --replay FILE` recomputes the sensor statistics from one.

## Watching it work

`--monitor` draws the signal against the thresholds it has to cross, because
the interesting failure is never a wrong decision — it is a gesture the
detector was never given the chance to see.

```
   66 │────────────────────────────────────────────────────────  baseline
   49 │┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  release
      │▃▃▃▃▃▃▃▃         ▁▁▂▂▃▃▁▁▁▁▃▃▂▂▂▂▂▂▁▁▁▁▁▁▂▂▂▂▃▃▂▂▁▁▁▁▁▁
   30 │┄┄┄┄┄┄┄┄██┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  cover
      └────────────────────────────────────────────────────────
       -9s                                                  now

       37 lux   base 66   state spent         uncover to re-arm
  signal  ███████████████████████████│██████···········│······   56%
                                     ^cover            ^release

  ▲ stalled between the thresholds for 11s: 56% of baseline is below release
    (75%) but above cover (45%), so nothing can complete. Usually
    auto-brightness dimming the screen.
```

The trace is coloured by detector state, so you can see what the state machine
believed at each sample rather than inferring it. The line at the bottom is the
part worth having: a signal that sits between the two thresholds can never
complete an edge, and the detector will look broken while behaving correctly.
Naming that costs one function, [`ls_diag`](src/ui.c), which is pure and
unit-tested like the rest of the recognition path.

It degrades on purpose. If stdout is not a terminal the whole escape-sequence
layer switches off and gestures print one per line, so `--monitor | tee log`
produces a log rather than a recording of cursor movements.

## Install

```bash
git clone https://github.com/ConnorXTan/lightswitch
cd lightswitch
make
sudo make install      # /usr/local/bin/lightswitch, or PREFIX=~/.local make install
```

Only a C11 compiler is needed. No dependencies.

## Using it

```bash
lightswitch                       # the product: glow around the notch, cover it
                                  # to toggle play/pause
lightswitch --headless            # the same control without the window (launchd)
lightswitch --dry-run             # recognise and print, act on nothing
lightswitch --monitor             # live view: signal, thresholds, diagnosis
lightswitch --calibrate           # measure your sensor and check your room
lightswitch --on-hold key:cmd+w   # rebind: gestures instead of the switch
```

Bind gestures with `--on-tap`, `--on-double-tap`, `--on-hold`, each taking:

| Spec | Effect |
| --- | --- |
| `none` | recognise and log, do nothing |
| `key:cmd+w` | send a keystroke to the focused app (`--list-keys` for names) |
| `exec:CMD` | run `CMD` with `/bin/sh` |
| `media:playpause` | press a media key: `playpause`, `next`, `prev`, `mute` |

**Or skip gestures entirely.** `--switch` turns the sensor into a plain
on/off switch: covering it fires `on`, uncovering fires `off` — bound with
`--on-cover` / `--on-uncover` (binding either implies `--switch`). There is
nothing to wait out, so each edge fires at the debounce limit, ~300 ms after
your hand — roughly a second faster than a tap can ever be:

```bash
lightswitch --on-cover media:playpause    # cover the notch to toggle the music
```

Settings live in `~/.config/lightswitch/config`, and any of them can be
overridden with `--set key=value`:

```ini
on_hold       = key:cmd+w
on_double_tap = exec:pmset displaysleepnow

cover_ratio   = 0.45   # trigger below 45% of baseline
hold_ms       = 1100   # cover this long to count as a hold
double_gap_ms = 600    # 0 disables double-tap and halves tap latency
```

See [`examples/config`](examples/config) for the annotated version, and
[`examples/com.lightswitch.agent.plist`](examples/com.lightswitch.agent.plist)
to run it at login.

### Which gesture to bind

**Bind `hold`.** It fires while your hand is still over the sensor, so it feels
immediate. A tap cannot: the detector has to wait out the double-tap window
before it knows the gesture is over, which costs about a second. If you want
snappy taps and no double-tap, set `double_gap_ms = 0`.

## How it works

The sensor reports absolute lux, so every threshold is a fraction of a running
baseline rather than a fixed level — the same gesture has to work at 200 lux
and 20,000 lux. Occluding the sensor drops the reading by ~100% against a
0.08% noise floor, so detection is never the hard part. The hard parts are:

- **Ambient drift.** Daylight fades, someone dims a lamp, the screen changes.
  The baseline follows this with a slow exponential average, but only while the
  sensor is idle and clearly uncovered — otherwise a resting hand would drag
  the baseline down onto itself and quietly disarm the detector.
- **A slow sensor.** It refreshes about every 211 ms while we poll at 100 ms, so
  consecutive polls often return the *same latched reading*. A two-sample
  debounce can therefore be satisfied twice by one hardware reading — it buys
  latency and no noise rejection at all. Three samples span 300 ms and
  guarantee two genuinely independent readings agree.
- **Things that are not gestures.** Someone walking past dims the sensor by
  20–30%. A Schmitt trigger (enter at 45%, leave at 75%) plus that debounce
  rejects them without rejecting real covers.

The full measurement write-up — noise floor, refresh rate, latency budget, and
why each constant is what it is — is in **[docs/SIGNAL.md](docs/SIGNAL.md)**.

## Architecture

The layering exists so the interesting logic is testable without hardware:

| Module | Role | Portable |
| --- | --- | --- |
| `src/detector.c` | baseline tracking, Schmitt trigger, gesture state machine | yes |
| `src/config.c` | one key/value namespace shared by file and CLI | yes |
| `src/action.c` | parse `key:`/`exec:`/`media:` specs; run them | parsing yes, running macOS |
| `src/trace.c` | record/replay format | yes |
| `src/glow.c` | the overlay's look as a pure function of the signal | yes |
| `src/sensor_iokit.c` | the real sensor, via private IOKit HID symbols | macOS only |
| `src/sensor_replay.c` | a recorded trace, same interface | yes |
| `src/overlay_macos.m` | the notch glow window; draws what `glow.c` decides | macOS only |
| `src/mediakey_macos.m` | posts media key events for `media:` actions | macOS only |
| `Lightswitch/Kit/Sessions` | session files → published list; slots, pruning, alerts | Swift, tested |
| `Lightswitch/Kit/Hooks` | `notch.sh` and the installer that merges it into `settings.json` | Swift, tested |
| `Lightswitch/Kit/Sensor` | `SensorEngine` wraps the C detector; `LightSensor` runs it on a thread | Swift, tested |
| `Lightswitch/Kit/Terminal` | which terminal owns a session and how to bring it forward | Swift, tested |
| `Lightswitch/App` | the notch window, shape, dots, list, settings, menu bar | Swift, AppKit + SwiftUI |

The app does not re-implement any of the C: `Package.swift` exposes `src/` and
`include/` to Swift as the `CLightswitch` module, so the gesture the app reacts
to is decided by the same `detector.c` the CLI and the fixtures use.

`detector.c` performs no I/O and calls nothing platform-specific: it takes
`(timestamp, lux)` and returns gestures. Everything awkward about the signal —
drift, dropouts, noise, jitter — is reproduced as fixtures in `tests/traces/`
and replayed identically on every run, so a bug found on hardware can be
recorded once and then chased offline.

Fixtures are generated by `tools/lstrace-synth.c`, which models the three
sensor properties that actually affect detection: sample-and-hold at 211 ms,
proportional noise, and the finite time a hand takes to arrive. Regenerate with
`make traces`.

```
make        build            make test     304 assertions, no hardware needed
make demo   replay fixtures  make traces   regenerate fixtures
make ci     -Werror + tests  make install  to $(PREFIX)/bin
make app    the notch app    swift test    the Swift suite
```

## Notes and limits

- The app's hooks are ordinary Claude Code hooks; `notch.sh` prints nothing,
  always exits 0, and needs nothing installed (`jq` if present, `plutil`
  otherwise), so it can never block or slow a session.
- Turn off **System Settings → Displays → "Automatically adjust brightness"**,
  or macOS dims the screen as you shade the sensor and fights the detection.
- `key:` and `media:` actions need Accessibility permission (**Privacy &
  Security → Accessibility**). `exec:` actions do not.
- `--overlay` composes with `--replay FILE --realtime`, which is how to demo
  the glow on a machine with no sensor.
- Needs a lit room. Below ~25 lux a hand shadow is not distinguishable from the
  room and lightswitch refuses to arm rather than firing at random.
- A gesture shorter than ~400 ms is shorter than two sensor refreshes and will
  not register reliably. That is a hardware floor, not a tuning problem.
- The ALS is reached through private IOKit symbols resolved at runtime. They
  have been stable for years but Apple does not promise that; if they ever
  disappear, `ls_sensor_open_iokit` fails with a clear message instead of
  crashing, and the rest of the program still works against traces.

## touchprobe

`tools/touchprobe.c` is a recorded negative result. This project started as an
attempt to use the **Touch ID sensor** as a scroll wheel; touchprobe measures
what an unprivileged process can actually learn from it, and the answer is
nothing useful — the sensor sits in `mesa-state 1` (asleep) and reports no
images or interrupts unless something has already requested authentication.

```bash
make build/touchprobe && ./build/touchprobe 25
```

The ambient light sensor was the input that turned out to be readable, which is
why the project ended up here.

## License

MIT — see [LICENSE](LICENSE).
