# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

(Not one of the schema's listed values. Lightswitch is a native macOS menu-bar
utility built with AppKit and SwiftUI; there is no web, iOS, or Android
surface.)

## Stack

Swift Package Manager package with three targets: `CLightswitch` (the existing
C11 gesture engine in `src/` and `include/`, compiled as-is), `LightswitchKit`
(Swift logic that needs no window: sessions, hooks, sensor bridge, terminal
focus) and `Lightswitch` (the AppKit/SwiftUI shell). No third-party
dependencies. `make app` wraps the release binary as `Lightswitch.app`.

## Users

One person: the developer who runs several Claude Code sessions in terminal
tabs on a MacBook and loses track of which one is waiting on them. They work
in VS Code's integrated terminal today (assumption from this session's
`TERM_PROGRAM`); iTerm and Terminal are also supported.

## Product Purpose

Turn the MacBook notch into a status light for Claude Code. One dot per
session, coloured by state, so a glance at the top of the screen answers "is
anything waiting on me?" without switching windows. The ambient light sensor
under the notch is a button: cover it to acknowledge the session that needs
you and jump to its terminal. Success is never missing a permission prompt in
a background session again, and never checking a tab that is still working.

## Positioning

The notch is dead space that every other app avoids; Lightswitch is the one
that lives in it. No other Claude Code status tool uses hardware the machine
already has (the notch, the light sensor) instead of a window, a Dock badge
or a notification.

## Operating Context

- Claude Code sessions report state through hooks in `~/.claude/settings.json`
  that run `~/.claude/hooks/notch.sh`, which writes one JSON file per session
  under `~/.claude-notch/sessions/`. The app watches that folder.
- Sessions live in terminal tabs (VS Code, iTerm, Terminal, others). The app
  activates the right one when a dot is clicked or the sensor is covered.
- The light sensor needs a lit room (over 25 lux) and "Automatically adjust
  brightness" turned off. Below that, the gesture is disabled and the app
  degrades to hover and click.
- Runs as a menu-bar accessory (no Dock icon) on macOS 14 or newer, on every
  display or the built-in one.

## Capabilities and Constraints

- States: idle (grey), working (yellow), needs you (red, pulsing until
  acknowledged), done (green; slow pulse when Claude has been waiting a while).
- Up to four dots in the closed notch; further sessions appear only in the
  open list with a "+N" marker.
- Open notch: one row per session with folder name, state and time since the
  last change; click a row to focus its terminal.
- When a session turns red, the notch widens for three seconds to show the
  folder name and "needs you", and plays a sound if enabled.
- Hooks are installed and removed by the app; it merges into
  `~/.claude/settings.json` with a backup and refuses invalid JSON.
- App Sandbox is off (the sensor is reached through private IOKit HID calls).
- Not covered: Cowork and cloud sessions (no local hooks), remote machines,
  the App Store, Windows or Linux.
- Undecided: whether dots should also show on the lock screen (currently no).

## Brand Commitments

The name is "Lightswitch". The existing CLI keeps its identity (glow ring,
gesture engine, `make demo`); the app is the same project growing a face. Copy
is plain and short, in the voice of the README: measured, a little dry, never
marketing.

## Evidence on Hand

- The measured sensor characterisation in `docs/SIGNAL.md` (refresh rate,
  noise floor, thresholds) and the 304-assertion C suite behind the detector.
- `PLAN.md`, the overhaul plan this build implements.
- No screenshots, testimonials or press. Nothing may be invented.

## Product Principles

- The app is optional. Sessions run exactly the same with it closed; state
  lives in files it only reads.
- Glanceable first. The closed notch must be readable in under a second and
  must never demand attention it did not earn.
- Reuse the tested engine. Gesture recognition stays in the C detector; Swift
  wraps it rather than re-implementing it.
- Degrade, never block. Missing private APIs, a dark room, an unknown terminal:
  each removes one feature and leaves the rest working.
- Native vocabulary. System font, system colours, standard settings controls;
  personality lives in the dots and the motion, not in chrome.

## Accessibility & Inclusion

Colour is never the only signal: the open list names each state in words, the
red state also pulses, and the alert peek is text. Reduce Motion is respected
for the pulse (assumption: to be honoured in implementation).
