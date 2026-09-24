---
name: Lightswitch
description: The MacBook notch as a status light for Claude Code sessions.
colors:
  notch-black: "#000000"
  white: "#ffffff"
  white-90: "rgba(255, 255, 255, 0.90)"
  white-85: "rgba(255, 255, 255, 0.85)"
  white-60: "rgba(255, 255, 255, 0.60)"
  white-55: "rgba(255, 255, 255, 0.55)"
  white-45: "rgba(255, 255, 255, 0.45)"
  white-40: "rgba(255, 255, 255, 0.40)"
  white-32: "rgba(255, 255, 255, 0.32)"
  white-14: "rgba(255, 255, 255, 0.14)"
  white-09: "rgba(255, 255, 255, 0.09)"
  state-working: "systemYellow"
  state-needs-you: "systemRed"
  state-done: "systemGreen"
  settings-accent: "accentColor"
  settings-warning: "systemOrange"
  settings-error: "systemRed"
  settings-secondary: "secondary"
  settings-track: "quaternary"
  icon-tile-top: "#29292e"
  icon-tile-bottom: "#121214"
typography:
  title:
    fontFamily: "system-ui"
    fontSize: "13px"
    fontWeight: 600
  title-tinted:
    fontFamily: "system-ui"
    fontSize: "13px"
    fontWeight: 500
  label:
    fontFamily: "system-ui"
    fontSize: "12px"
    fontWeight: 500
  meta:
    fontFamily: "system-ui"
    fontSize: "12px"
    fontWeight: 400
    fontVariation: "tabular-nums"
  button:
    fontFamily: "system-ui"
    fontSize: "12px"
    fontWeight: 600
  caption:
    fontFamily: "system-ui"
    fontSize: "11px"
    fontWeight: 600
  caption-count:
    fontFamily: "system-ui"
    fontSize: "11px"
    fontWeight: 500
    fontVariation: "tabular-nums"
  mono:
    fontFamily: "ui-monospace"
    fontSize: "11px"
    fontWeight: 400
  counter:
    fontFamily: "ui-rounded"
    fontSize: "10px"
    fontWeight: 600
    fontVariation: "tabular-nums"
  settings-body:
    fontFamily: "system-ui"
    fontSize: "13px"
    fontWeight: 400
  settings-callout:
    fontFamily: "system-ui"
    fontSize: "12px"
    fontWeight: 400
rounded:
  closed-top: "6px"
  closed-bottom: "14px"
  open-top: "19px"
  open-bottom: "24px"
  row: "8px"
  pill: "9999px"
spacing:
  hairline: "1px"
  xs: "4px"
  sm: "6px"
  md: "10px"
  dot-lead: "12px"
  dot-trail: "18px"
  peek-x: "24px"
components:
  session-dot:
    size: "8px"
    rounded: "{rounded.pill}"
  session-dot-idle:
    backgroundColor: "{colors.white-32}"
  session-dot-working:
    backgroundColor: "{colors.state-working}"
  session-dot-needs-you:
    backgroundColor: "{colors.state-needs-you}"
  session-dot-done:
    backgroundColor: "{colors.state-done}"
  overflow-counter:
    textColor: "{colors.white-60}"
    typography: "{typography.counter}"
    width: "20px"
  closed-notch:
    backgroundColor: "{colors.notch-black}"
    padding: "0 10px"
  peek:
    backgroundColor: "{colors.notch-black}"
    padding: "0 24px"
    width: "640px"
  peek-title:
    textColor: "{colors.white}"
    typography: "{typography.title}"
  peek-detail:
    typography: "{typography.title-tinted}"
  open-panel:
    backgroundColor: "{colors.notch-black}"
    padding: "0 10px 10px"
    width: "400px"
  panel-header-title:
    textColor: "{colors.white-55}"
    typography: "{typography.caption}"
  panel-header-summary:
    textColor: "{colors.white-45}"
    typography: "{typography.caption-count}"
  session-row:
    rounded: "{rounded.row}"
    padding: "0 10px"
    height: "32px"
  session-row-hover:
    backgroundColor: "{colors.white-09}"
  session-row-name:
    textColor: "{colors.white}"
    typography: "{typography.title}"
  session-row-id:
    textColor: "{colors.white-40}"
    typography: "{typography.mono}"
  session-row-state:
    typography: "{typography.label}"
  session-row-state-idle:
    textColor: "{colors.white-45}"
  session-row-age:
    textColor: "{colors.white-40}"
    typography: "{typography.meta}"
    width: "32px"
  empty-title:
    textColor: "{colors.white-85}"
    typography: "{typography.title}"
  empty-body:
    textColor: "{colors.white-45}"
    typography: "{typography.settings-callout}"
  button-install:
    backgroundColor: "{colors.white-14}"
    textColor: "{colors.white}"
    typography: "{typography.button}"
    rounded: "{rounded.pill}"
    padding: "5px 12px"
  ratio-bar:
    backgroundColor: "{colors.settings-track}"
    rounded: "{rounded.pill}"
    width: "180px"
    height: "6px"
  ratio-bar-fill:
    backgroundColor: "{colors.settings-accent}"
  ratio-bar-fill-covered:
    backgroundColor: "{colors.settings-warning}"
  settings-form:
    width: "460px"
---

# Design System: Lightswitch

## Overview

**Creative North Star: "The Status Light"**

Lightswitch draws nothing of its own except a black shape that extends the
MacBook's notch and the coloured dots inside it. The world is the platform's:
the system font at 10 to 13 pt, the system's semantic status colours, standard
grouped Settings controls, a text-only menu bar menu. Personality lives in the
dots and in motion that only ever means a change of state.

Density is high and fixed. The closed notch is a row of 8 pt dots at 10 pt
spacing; the open panel is a 440 pt list of 28 pt rows. Nothing decorative is
drawn behind the physical notch, which has no pixels: layouts leave a clear
gap exactly the notch's measured width.

**Key Characteristics:**
- Pure black shape, white text at opacity steps, three system state colours.
- One typeface (system), sizes 10 to 13 pt, monospaced digits wherever numbers tick.
- Motion is state: springs for open/close, a pulse for "needs you", a slow breathe for "done and waiting", nothing at rest.
- Shadows appear only in response to state; at rest every shadow is opacity 0.
- Reduce Motion swaps the pulse for a white ring; every dot and row carries a spoken label.

## Colors

A black ground, white at fixed opacity steps, and the Mac's own status colours.

### Primary
- **Needs You** (`systemRed`): the dot and the state word when a session is waiting on a permission prompt. Pulses until acknowledged. Also the Settings error text colour.
- **Working** (`systemYellow`): the dot and state word while Claude is running.
- **Done** (`systemGreen`): the dot and state word when a turn has finished; also the Settings "hooks installed" status dot.

### Neutral
- **Notch Black** (`#000000`): the fill of every notch shape, closed, peeking or open, and the notch drawn in the app icon.
- **White** (`#ffffff`): folder names, the peek title, the install button label.
- **White 90**: the Reduce Motion ring around an unacknowledged red dot.
- **White 85**: empty-state headings ("No sessions", "Hooks not installed").
- **White 60**: the "+N" overflow counter in the closed notch.
- **White 55**: the open panel's "Claude Code" header title.
- **White 45**: the panel summary ("2 need you"), the idle state word, empty-state body copy.
- **White 40**: the short session ID and the age column.
- **White 32**: the idle dot, and the idle dot in the app icon. Dim white rather than grey so it still reads on black.
- **White 14**: the install button's capsule fill.
- **White 09**: the session row hover fill.

### Settings (system semantics, adaptive to light and dark)
- **Accent** (`accentColor`): the ratio bar's fill while the sensor is armed.
- **Warning** (`systemOrange`): the ratio bar's fill once the reading drops below the cover threshold.
- **Secondary** (`.secondary`): footers, "Needs Accessibility permission", the ratio bar's threshold ticks; at 50 % opacity, the hooks status dot when hooks are not installed.
- **Track** (`.quaternary`): the ratio bar's empty capsule.

### App icon (frozen values)
- **Icon Tile** (`#29292e` to `#121214`, top to bottom): the squircle behind the notch in the app icon; a faint top light on a dark, slightly cool grey.
- The icon cannot use dynamic colours, so it freezes the three state colours at their dark-appearance values (`#30d159`, `#ffd60a`, `#ff453b`) and the idle dot at white 32 %. The app itself always uses the system names.

### Named Rules
**The Dim White Rule.** On the notch, every non-state colour is white at an opacity step (9, 14, 32, 40, 45, 55, 60, 85, 90, 100 %). No grey hex ever appears on black.

**The Words Beside Colour Rule.** A state colour never stands alone. In the open list and the peek the state is also a word; in the closed notch the dot's accessibility label speaks it; red adds motion (or the ring).

## Typography

**Body Font:** System (SF, via `.system(size:weight:)`)
**Mono Font:** System monospaced (`design: .monospaced`), 11 pt, for short session IDs only
**Counter Font:** System rounded (`design: .rounded`), 10 pt, for the "+N" overflow only

**Character:** The platform's own face, never larger than 13 pt. Weight does the hierarchy work: semibold names, medium state words, regular meta.

### Hierarchy
- **Title** (600, 13 pt): folder names in rows, the peek title, empty-state headings.
- **Title, tinted** (500, 13 pt): the peek detail ("needs you"), coloured with the state.
- **Label** (500, 12 pt): the state word beside each row's dot.
- **Meta** (400, 12 pt, monospaced digits): the age column ("3m"), empty-state body copy.
- **Button** (600, 12 pt): the "Install hooks" capsule.
- **Caption** (600, 11 pt): the open panel's "Claude Code" header.
- **Caption, counting** (500, 11 pt, monospaced digits): the panel summary.
- **Mono** (400, 11 pt, monospaced): the short session ID, shown only when two sessions share a folder name.
- **Counter** (600, 10 pt, rounded, monospaced digits): "+N".
- **Settings** uses the system text styles untouched: body for controls and footers, `.callout` (12 pt) for error lines. The menu is the system menu font.

### Named Rules
**The Counting Digits Rule.** Anything that counts or ticks (the summary, the age, "+N", the lux readout) uses monospaced digits so it does not jitter.

## Layout

Every notch window is a fixed transparent canvas of 640 × 280 pt, top-aligned,
centred on the physical notch (not the screen). The closed shape's size is
measured per screen: the notch's width plus a 2 pt bleed each side, and the
notch's height (or the menu bar height on displays without a notch).

- **Closed, notched display:** the notch itself is a clear frame; a narrow black wing to its right holds the dots in a two-row grid (7 pt dots, 5 pt gaps, columns filled top to bottom). Wing width = 8 pt leading + columns + 12 pt trailing (the trailing 12 includes the 6 pt top flare, so 6 pt reads as margin): one column (1–2 sessions) 27 pt, two 39 pt, three (5–6) 51 pt; with "+N" (16 pt wide, after one more 5 pt gap) 72 pt. The whole shape shifts right by half the wing so the notch part stays over the hardware. Kept this narrow (a 6-session wing is 51 pt against the earlier 92 pt for four) so the menu bar extras beside the notch stay uncovered; a floating, centred island was tried and rejected on 2026-09-24 in favour of the attached rectangle.
- **Closed, other displays:** a black pill over the menu bar, dots centred, 10 pt horizontal inset.
- **Peek:** the closed shape widened to 640 pt, 24 pt horizontal padding; title right-aligned left of the notch, detail left-aligned right of it, with a clear gap of the notch width + 10 pt between. Without a notch, the two sit in one pill 8 pt apart.
- **Open:** 440 pt wide (was 400; beside the header's clear notch gap each side has 87 pt, enough for "Claude Code" at 70 pt and "12 terminals" at 65 pt on one line), 23 pt horizontal padding (the 19 pt top flare, inside which the shape's sides sit, plus 4 pt, so text lands 14 pt inside the visible edge and row dots 26 pt) and 10 pt bottom padding, 4 pt between header and list. The header row is the closed height and leaves the same notch-width + 10 pt clear gap in its middle. Rows are 32 pt with 1 pt between; after six rows the list scrolls at 6 × 33 = 198 pt.
- **Row:** 10 pt horizontal padding, 10 pt between dot, name, ID and state; the age column is a fixed 32 pt, right-aligned; at least 8 pt of spacer before the state word.
- **Empty state:** centred, 6 pt vertical rhythm, minimum 64 pt tall, 6 pt vertical padding.
- **Settings:** a grouped Form, 460 pt wide, three sections (Notch, Light sensor, Claude Code hooks). The ratio bar is 180 × 6 pt.
- **Dot slots:** six fixed slots, three columns of two. Empty slots keep their space so a dot never shifts when a session before it ends.

## Elevation & Depth

Flat by default. The black shape sits on the bezel with no edge at rest; depth
appears only as a response to state.

### Shadow Vocabulary
- **Panel lift** (`black 50 %, radius 14, y 8`): on the whole shape while open or hovered; opacity 0 otherwise.
- **Dot glow** (state colour, `radius 2 at 35 %` ↔ `radius 5 at 90 %`): only on an unacknowledged red dot, alternating with the pulse; opacity 0 at rest on every other dot.
- **Icon glow** (red at 90 %, blur 0.9 × dot): the red dot in the app icon only.

### Named Rules
**The Shadow-On-State Rule.** No surface carries a shadow at rest. The panel's shadow arrives with open or hover; the dot's arrives with the pulse; both return to 0.

## Shapes

The notch silhouette (`NotchShape`): a rectangle whose top corners flare
*outward* into the screen edge (a quadratic curve from the very corner, radius
`t`) so the black blends into the bezel, and whose bottom corners round inward
(radius `b`). Closed: t 6, b 14. Open: t 19, b 24. The radii animate
during the open and close, inside `RevealShape`: the panel's outline grows
from the whole closed box, wing included, so the box is what expands (its
centre moves 25 pt left over the growth, as part of the one motion). The app icon draws the same silhouette at t = 10 % and
b = 30 % of its notch height, hanging from a squircle tile with corner radius
22.5 % of the tile.

Inside the shape: dots are circles; rows are 8 pt continuous-corner rounded
rectangles; the install button and the ratio bar are capsules.

## Components

### Session Dot
- **Shape:** 8 pt circle in list rows, 7 pt in the wing; tap target inset −5 pt in rows (18 pt hit area) and −2.5 pt in the wing (12 pt, the row pitch).
- **Colour:** white 32 % idle; `systemYellow` working; `systemRed` needs you; `systemGreen` done.
- **Needs you, unacknowledged:** scales 1 → 1.4 and glows, `easeInOut 0.8 s`, repeating and reversing. Acknowledging stops it; the dot settles with `easeOut 0.2 s`.
- **Done and idle (Claude has been waiting a while):** breathes 1 → 0.45 opacity, `easeInOut 2.2 s`, repeating and reversing.
- **Reduce Motion:** no pulse or breathe; an unacknowledged red dot gets a 1.5 pt white 90 % ring at dot + 6 pt instead.
- **Accessibility:** "*folder* needs you" / "*folder* is working" / "is done" / "is idle".

### Dots Grid (closed notch)
- One dot per slot, two rows, 5 pt gaps; slot 1 top-left, slot 2 under it, slot 3 tops the next column. Empty slots keep their place; trailing empty columns collapse.
- More sessions than slots: "+N" in counter type at white 60 %, 16 pt wide, labelled "N more sessions".
- Column count changes animate with `smooth 0.25 s`; the wing width with `smooth 0.3 s`.
- Tapping the dots row toggles the panel; tapping a dot focuses that session's terminal.

### Peek
- The closed shape widened to 640 pt for 3 s when a session turns red (`smooth 0.3 s`, fading in and out).
- Title: folder name, 13 pt semibold white, middle-truncated. Detail: the state word, 13 pt medium in the state's colour.

### Open Panel Header
- Left: "Claude Code", 11 pt semibold at white 55 %. Right: the summary ("1 needs you", "6 terminals"; the project count is not shown, the headers below carry it), 11 pt medium, monospaced digits, white 45 %. Both one line. The middle is clear over the notch.
- The panel grows out of the notch and shrinks back into it (`Reveal`): an animated clip on the panel that starts as the whole closed box (notch plus wing, closed radii, exactly where the closed shape sits) and expands to the panel's outline in one motion, radii interpolating 6/14 → 19/24; the shadow is applied after the clip and fades in with it. Content is revealed by the clip, never faded. The closed layout sits above the panel: its dots fade out over 0.12 s as the box starts to grow, and fade back in over 0.1 s from 0.35 s into the close, as the box finishes shrinking. Open spring `response 0.36, damping 0.86` (it arrives, it does not bounce); close spring `response 0.45, damping 1.0`. The peek uses the same reveal, without a shadow.
- Opens after the pointer rests 300 ms; closes 100 ms after it leaves.

### Session Row
- 32 pt tall, 10 pt padding, 8 pt continuous corners.
- Dot, folder name (13 pt semibold white, middle-truncated), optional short ID (11 pt mono, white 40 %), state word (12 pt medium in the state colour; white 45 % for idle), age (12 pt, monospaced digits, white 40 %, 32 pt column).
- **Hover:** white 9 % fill, `easeOut 0.12 s`. Click focuses the terminal.
- **Accessibility:** one element, button trait, "*folder* needs you, 3m".

### Empty State
- Heading 13 pt semibold white 85 %, body 12 pt white 45 %, centred, 6 pt apart.
- "No sessions" + "Start `claude` in a terminal and a dot appears here." when hooks are installed; "Hooks not installed" + explanation + the install button otherwise.

### Buttons
- **Install hooks (on the notch):** 12 pt semibold white on a white 14 % capsule, 12 × 5 pt padding, plain button style, 4 pt above.
- **Settings and menu:** standard system buttons ("Recalibrate", "Install hooks", "Remove hooks", "Show script in Finder"), disabled when not applicable.

### Ratio Bar (Settings)
- 180 × 6 pt capsule track in `.quaternary`; fill in the accent colour, or `systemOrange` once below the cover threshold; width = clamped reading ÷ baseline, `linear 0.1 s`.
- Two 1 pt `.secondary` ticks, 4 pt taller than the bar, at the cover and uncover thresholds.
- Labelled "Light level N percent of baseline".

### Settings Form
- Grouped form style, 460 pt wide. Toggles, a picker, `LabeledContent` rows, secondary-colour footers. Errors in `.callout`, `systemRed`. Hooks status: an 8 pt circle, `systemGreen` when installed, secondary at 50 % otherwise.

### Status Menu and Icon
- **Icon:** 18 pt template image, a 2 × 2 grid of 3 pt dots with 1.5 pt gaps; follows the menu bar's light or dark appearance.
- **Menu:** a summary line ("2 sessions · 1 needs you" or "Hooks not installed"), then text items and dividers only: Install Claude Code Hooks…, Open Notch, Launch at Login, Settings… (⌘,), Quit Lightswitch (⌘Q).

### App Icon
- Dark squircle tile (10 % inset, 22.5 % corners, vertical gradient) with the notch silhouette hanging from its top edge at 62 % width and 30 % height; four dots inside at 26 % of the notch height, gaps 1.1 × dot, in the order done, working, needs you (glowing), idle.

## Do's and Don'ts

### Do:
- **Do** fill every notch shape with pure black and put nothing on it except white at an opacity step or a system state colour.
- **Do** keep type in the system font between 10 and 13 pt and use monospaced digits for anything that counts.
- **Do** pair every state colour with its word (row label, peek detail) or its spoken label.
- **Do** animate only state changes: springs for open/close, `smooth 0.3` for the peek, the pulse for unacknowledged red, the breathe for done-and-waiting, `easeOut 0.12` for row hover.
- **Do** honour Reduce Motion: no pulse, no breathe, the white ring instead.
- **Do** keep the four dot slots fixed and overflow into "+N".
- **Do** use standard grouped Form controls in Settings; draw custom only the ratio bar and the 8 pt status dot.

### Don't:
- **Don't** draw behind the physical notch; leave the measured gap clear in the closed, peek and open layouts.
- **Don't** introduce a custom typeface, glyph icons or bitmap images: the menu bar icon and app icon are drawn dots and the notch silhouette.
- **Don't** give a surface a shadow at rest; the panel lift and dot glow are opacity 0 until open, hover or pulse.
- **Don't** use grey for idle or for secondary text on black; use white at the recorded opacity.
- **Don't** tint chrome with a state colour; red, yellow and green appear on dots, state words and the peek detail only (and, in Settings, `systemRed` for errors and `systemOrange` for the covered sensor).

## Addendum (2026-09-24, projects branch)

The open panel lists sessions grouped by repository (the working
directory's git root, a linked worktree resolved to its main worktree; the
directory itself outside git). `ProjectHeader`
(26 pt: folder name 13/600 white, location 11/400 white-40 only when two
projects share a name, "N terminals" 11/400 white-40 tabular on the right)
sits above `SessionRow`s (28 pt, indented 22 pt: dot, the session's name
12/500 white-85 tail-truncated (Claude Code's generated title or a
`/rename`; before it has one, "App · tty" middle-truncated, and the
terminal is always the row's tooltip), then the subfolder or worktree name
11/400 white-40 when the session is not at the root, state word, age). Groups are separated by 6 pt; the list scrolls
past nine rows at a 262 pt cap. The window canvas is 640×360.
