# Signal characterisation

Every constant in `ls_detector_config_defaults` comes from a measurement.
This is where they come from, and what would change them.

All figures below were taken on a MacBook Pro (Vishay VD6286 ambient light
sensor, behind the display glass beside the camera) using
`lightswitch --calibrate`, which is built for exactly this purpose.

## The sensor

```
$ lightswitch --calibrate 8
samples          80 over 8.0s (polled every 100 ms)
dropped reads    0
mean             6198.6 lux
range            6167.0 .. 6224.0 lux
refresh rate     ~4.4 Hz (value changed 35 times)
short-term noise 4.67 lux (0.075% of mean, 1 sigma between updates)
ambient drift    -35 lux over the window (0.6% of mean)
```

| Property | Measured | Consequence |
| --- | --- | --- |
| Refresh rate | 4.4–4.7 Hz (~211 ms) | sets every latency floor in the system |
| Short-term noise | 0.075–0.12% of reading, 1σ | far too small to cause false triggers |
| Occlusion depth | ~98–100% drop | detection is trivially separable |
| Reported quantity | absolute lux | thresholds must be relative, not fixed |
| Dropped reads | 0 in 80 | rare, but handled as "ignore", not "dark" |

### Measuring noise without measuring the room

The obvious approach — standard deviation of all readings — is wrong here, and
wrong by a lot. An early version of `--calibrate` reported "noise" of **2.96%**
in a room whose actual sensor noise is 0.075%. The difference was the room
itself getting brighter over the eight-second window; total spread mixes sensor
noise with genuine ambient change and is dominated by whichever is larger.

`--calibrate` instead takes the standard deviation of the *difference between
consecutive distinct readings*. Differencing cancels any slow trend, leaving
only the short-term component. Since the variance of a difference of two
independent samples is twice the sample variance, the result is divided by √2.
Drift is then reported separately as first-reading-to-last.

This matters because the two numbers imply different fixes: high noise means
raise the debounce, high drift means the room is unstable and the cover
threshold needs more margin.

## Why thresholds are ratios

The sensor reports absolute illuminance, and the useful range spans two orders
of magnitude — a dim room is ~200 lux, a bright office ~5,000, near a window
20,000+. A fixed lux threshold calibrated indoors triggers constantly outdoors
and never triggers at dusk.

Everything is therefore expressed as a fraction of a running baseline:

```
cover_ratio   = 0.45    enter "covered" below 45% of baseline
uncover_ratio = 0.75    leave "covered" above 75% of baseline
```

With a 55% margin to the trigger and a 0.1% noise floor, the margin against a
noise-driven false trigger is roughly **500σ**. Noise is not the constraint;
the room is. On the measurement above, the deepest dip observed while uncovered
was 0.5% of baseline, still a 108x margin.

The two thresholds differ (a Schmitt trigger) because a signal hovering near a
single threshold produces a burst of spurious edges. A hand crosses the whole
range in well under one sample period, so the 30-point gap costs no real
latency while making chatter impossible.

## The sample-and-hold trap

The sensor refreshes every ~211 ms. lightswitch polls every 100 ms. Consecutive
polls therefore frequently return **the same latched hardware reading**:

```
0.2    6184.00
101.3  6184.00     <- same reading, polled again
205.2  6186.00     <- sensor refreshed
301.2  6186.00     <- same reading, polled again
```

The consequence for debouncing is easy to get wrong. A debounce of two
consecutive samples looks like it requires "two agreeing readings", but at this
poll rate both samples are often one hardware reading counted twice. It adds
100 ms of latency and rejects nothing.

To guarantee two genuinely independent readings agree, the debounce window must
exceed the refresh period:

```
debounce_samples x poll_ms  >  211 ms
3 x 100 ms = 300 ms         ✓
```

Hence `debounce_samples = 3`. `--calibrate` prints this requirement for your
machine, because the refresh rate is not identical across models.

The same aliasing bit the *fixture generator*: an early `lstrace-synth` snapped
the sensor's refresh grid onto the poll grid, which made a 300 ms gesture land
exactly between two refreshes and disappear from the trace. The two clocks are
independent in hardware and have to be independent in the model.

## Latency budget

Detecting an edge costs quantisation plus debounce:

```
waiting for the next sensor refresh    0 .. 211 ms   (~105 ms average)
debounce                                     300 ms
                                       -------------
edge detected                          300 .. 511 ms
```

From there each gesture adds its own decision time:

| Gesture | Fires when | Latency from hand arriving |
| --- | --- | --- |
| hold | `hold_ms` after the cover edge, hand still there | ~1.4–1.6 s |
| tap | `double_gap_ms` after the release edge | ~1.0–1.2 s |
| tap, `double_gap_ms=0` | on the release edge | ~0.5 s |
| double-tap | on the second cover edge | ~1.0 s |

**A tap is inherently slower than a hold**, because the detector cannot know a
tap is a tap until the double-tap window expires — while a hold announces
itself while your hand is still in place. This is why the README recommends
binding `hold` for anything that should feel instant, and why
`double_gap_ms = 0` exists for people who want fast taps more than they want
double-tap.

### Minimum gesture duration

A cover must last long enough for two distinct refreshes to fall inside it:

```
211 ms (worst-case wait for the first refresh)
+ 211 ms (the second refresh)
≈ 420 ms
```

Under ~400 ms, detection becomes probabilistic. This is a hardware floor. The
only way past it is a faster sensor.

## Timing constants

```
hold_ms       = 1100    cover longer than this is a hold
double_gap_ms =  600    second cover within this of release is a double-tap
refractory_ms =  700    ignore new gestures this long after firing one
```

`double_gap_ms` is set by jitter, not by human preference. Each detected edge
carries up to 211 ms of quantisation error, and the *gap* between two edges is
the difference of two such errors — so a deliberate 300 ms double tap can be
measured as anywhere from ~90 ms to ~510 ms. A 450 ms window (the original
value) catches that only sometimes: the `office_session` fixture was built with
a 400 ms gap and intermittently resolved as a single tap. 600 ms clears the
jitter.

The invariant `double_gap_ms < hold_ms` is enforced by
`ls_detector_config_validate`: if the gap were longer, a cover would still be
waiting to see whether it was a double-tap after it had already become a hold.

`refractory_ms` suppresses a second gesture immediately after one fires, which
mostly catches the hand lifting untidily. Covers that begin inside the window
are swallowed rather than queued — a queued gesture would fire the moment the
window expired, which feels like a phantom press.

## Rejecting things that are not gestures

| Event | Depth | Rejected by |
| --- | --- | --- |
| Sensor noise | ~0.1% | cover threshold, 500σ away |
| Someone walking past | 20–35% | cover threshold (needs 55%) |
| Cloud, lamp dimmed, dusk | slow, any depth | baseline tracking |
| Single corrupt reading | up to 100% | 3-sample debounce |
| Dropped read (negative) | n/a | ignored; timers do not advance |

The `walk_past` fixture encodes the second row: three partial shadows of 17%,
28% and 34%, all correctly ignored.

### Baseline tracking, and its limit

The baseline follows ambient drift with an exponential moving average,
`alpha = 0.005` per sample — a time constant of 200 samples, about 20 seconds
at 10 Hz. It updates **only** while the detector is idle and the reading is
above `uncover_ratio`. Without that guard, resting a hand over the sensor would
pull the baseline down toward the covered level, and the detector would quietly
disarm itself; `test_covered_hand_does_not_poison_baseline` pins this.

An EMA lags a linear ramp by `rate x tau`. At 20 s, tracking daylight fading
from 4830 to 2400 lux over five minutes leaves the baseline ~160 lux high — a
ratio of 0.94, comfortably above the 0.75 release threshold. Roughly, ambient
light may change by up to about **1% of baseline per second** before drift
alone starts approaching the trigger. Faster than that (walking outdoors, a
light switched off) and the detector re-baselines within a few seconds rather
than firing — a single spurious gesture at the moment of the change is
possible, which is what `refractory_ms` limits the damage from.

## What would change these numbers

- **A different Mac.** Refresh rate varies by model; run `--calibrate`.
- **Auto-brightness left on.** macOS dims the display as you shade the sensor,
  which changes the light reaching the sensor — a feedback loop the detector
  cannot see. Turn it off.
- **A very dark room.** Below ~25 lux the shadow is not separable and
  lightswitch faults out at calibration instead of firing at random.
- **An external display as primary.** The sensor is in the laptop lid; the
  gesture is over the laptop screen regardless of where the windows are.
