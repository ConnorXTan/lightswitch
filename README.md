# lightswitch

Turns the MacBook's ambient light sensor into a gesture input. Cup your hand
over the top-centre of the display and the shadow becomes a button: a quick
cover is a **tap**, two in a row are a **double-tap**, holding it there is a
**hold**. Each gesture runs whatever you bind it to.

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

`make test` runs the full suite (200 assertions) on any Unix machine, sensor or
not. That is the point of the layering — see [Architecture](#architecture).

`--replay` selects the *source*, not a mode, so it composes with the rest:
`--monitor --replay FILE` watches a recording play back, and
`--calibrate --replay FILE` recomputes the sensor statistics from one.

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
lightswitch                       # dry run: recognises and prints, acts on nothing
lightswitch --monitor             # live signal view, for aiming and tuning
lightswitch --calibrate           # measure your sensor and check your room
lightswitch --on-hold key:cmd+w   # bind a gesture and arm it
```

Bind gestures with `--on-tap`, `--on-double-tap`, `--on-hold`, each taking:

| Spec | Effect |
| --- | --- |
| `none` | recognise and log, do nothing |
| `key:cmd+w` | send a keystroke to the focused app (`--list-keys` for names) |
| `exec:CMD` | run `CMD` with `/bin/sh` |

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
| `src/action.c` | parse `key:`/`exec:` specs; run them | parsing yes, keystrokes macOS |
| `src/trace.c` | record/replay format | yes |
| `src/sensor_iokit.c` | the real sensor, via private IOKit HID symbols | macOS only |
| `src/sensor_replay.c` | a recorded trace, same interface | yes |

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
make        build            make test     198 assertions, no hardware needed
make demo   replay fixtures  make traces   regenerate fixtures
make ci     -Werror + tests  make install  to $(PREFIX)/bin
```

## Notes and limits

- Turn off **System Settings → Displays → "Automatically adjust brightness"**,
  or macOS dims the screen as you shade the sensor and fights the detection.
- `key:` actions need Accessibility permission (**Privacy & Security →
  Accessibility**). `exec:` actions do not.
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
