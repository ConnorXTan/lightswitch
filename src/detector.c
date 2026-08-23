#include "detector.h"

#include <stdio.h>
#include <string.h>

const char *ls_gesture_name(ls_gesture g)
{
    switch (g) {
    case LS_GESTURE_TAP:        return "tap";
    case LS_GESTURE_DOUBLE_TAP: return "double-tap";
    case LS_GESTURE_HOLD:       return "hold";
    case LS_GESTURE_ON:         return "on";
    case LS_GESTURE_OFF:        return "off";
    case LS_GESTURE_NONE:       break;
    }
    return "none";
}

const char *ls_state_name(ls_state s)
{
    switch (s) {
    case LS_STATE_CALIBRATING: return "calibrating";
    case LS_STATE_IDLE:        return "idle";
    case LS_STATE_COVERED:     return "covered";
    case LS_STATE_TAP_PENDING: return "tap-pending";
    case LS_STATE_SPENT:       return "spent";
    case LS_STATE_FAULT:       return "fault";
    }
    return "?";
}

void ls_detector_config_defaults(ls_detector_config *cfg)
{
    cfg->calibration_ms   = 2000.0;
    cfg->min_baseline_lux = 25.0;
    cfg->cover_ratio      = 0.45;
    cfg->uncover_ratio    = 0.75;
    /* Three polls at 100 ms span 300 ms, which exceeds the sensor's 211 ms
     * refresh period. That is the point: it guarantees at least two *distinct*
     * hardware readings agree before the cover state flips. A debounce of two
     * can be satisfied by the same latched reading polled twice, which buys
     * latency without buying any noise rejection. */
    cfg->debounce_samples = 3;
    /* The sensor refreshes near 4.7 Hz, so each detected edge carries up to
     * ~211 ms of quantisation error and the gap between two edges up to twice
     * that. double_gap_ms has to clear that jitter or a deliberate double-tap
     * intermittently resolves as one tap; 600 ms reliably catches a natural
     * ~300 ms double tap. Set it to 0 to drop double-tap and halve tap
     * latency. See docs/SIGNAL.md for the full budget. */
    cfg->hold_ms          = 1100.0;
    cfg->double_gap_ms    = 600.0;
    cfg->refractory_ms    = 700.0;
    cfg->baseline_alpha   = 0.005;
    cfg->switch_mode      = 0;
}

int ls_detector_config_validate(const ls_detector_config *cfg,
                                char *err, size_t errlen)
{
#define FAIL(msg) do { snprintf(err, errlen, "%s", (msg)); return -1; } while (0)
    if (cfg->calibration_ms < 100.0)
        FAIL("calibration_ms must be at least 100");
    if (cfg->min_baseline_lux < 0.0)
        FAIL("min_baseline_lux must not be negative");
    if (cfg->cover_ratio <= 0.0 || cfg->cover_ratio >= 1.0)
        FAIL("cover_ratio must be between 0 and 1 (exclusive)");
    if (cfg->uncover_ratio <= 0.0 || cfg->uncover_ratio >= 1.0)
        FAIL("uncover_ratio must be between 0 and 1 (exclusive)");
    if (cfg->cover_ratio >= cfg->uncover_ratio)
        FAIL("cover_ratio must be below uncover_ratio, or the trigger will chatter");
    if (cfg->debounce_samples < 1)
        FAIL("debounce_samples must be at least 1");
    if (cfg->hold_ms <= 0.0)
        FAIL("hold_ms must be positive");
    if (cfg->double_gap_ms < 0.0)
        FAIL("double_gap_ms must not be negative (use 0 to disable double-tap)");
    if (cfg->double_gap_ms >= cfg->hold_ms)
        FAIL("double_gap_ms must be below hold_ms, or a hold can never resolve");
    if (cfg->refractory_ms < 0.0)
        FAIL("refractory_ms must not be negative");
    if (cfg->baseline_alpha < 0.0 || cfg->baseline_alpha >= 1.0)
        FAIL("baseline_alpha must be in [0, 1)");
#undef FAIL
    return 0;
}

void ls_detector_init(ls_detector *d, const ls_detector_config *cfg)
{
    memset(d, 0, sizeof(*d));
    d->cfg   = *cfg;
    d->state = LS_STATE_CALIBRATING;
}

static void fault(ls_detector *d, const char *msg)
{
    d->state = LS_STATE_FAULT;
    snprintf(d->fault, sizeof(d->fault), "%s", msg);
}

/* Schmitt trigger with an N-of-N debounce.
 *
 * The two thresholds are deliberately far apart: a hand entering or leaving
 * the sensor sweeps the whole range in well under one sample period, so the
 * gap costs nothing in latency but makes it impossible for noise around a
 * single threshold to produce a burst of spurious edges.
 *
 * Returns 1 if the debounced cover flag changed on this sample. */
static int update_cover(ls_detector *d)
{
    int want = d->covered;
    if (!d->covered && d->last_ratio < d->cfg.cover_ratio)
        want = 1;
    else if (d->covered && d->last_ratio > d->cfg.uncover_ratio)
        want = 0;

    if (want == d->covered) {
        d->streak = 0;
        d->streak_target = d->covered;
        return 0;
    }
    if (d->streak_target != want) {
        d->streak_target = want;
        d->streak = 0;
    }
    if (++d->streak >= d->cfg.debounce_samples) {
        d->covered = want;
        d->streak  = 0;
        return 1;
    }
    return 0;
}

ls_gesture ls_detector_push(ls_detector *d, double t_ms, double lux)
{
    if (d->state == LS_STATE_FAULT)
        return LS_GESTURE_NONE;
    if (lux < 0.0)
        return LS_GESTURE_NONE; /* dropped read; hold all timers */

    d->t_last  = t_ms;
    d->last_lux = lux;

    if (d->state == LS_STATE_CALIBRATING) {
        if (d->calib_n == 0)
            d->t_first = t_ms;
        d->calib_sum += lux;
        d->calib_n++;
        if (t_ms - d->t_first >= d->cfg.calibration_ms) {
            d->baseline = d->calib_sum / (double)d->calib_n;
            if (d->baseline < d->cfg.min_baseline_lux) {
                char msg[160];
                snprintf(msg, sizeof(msg),
                         "ambient light too low (%.0f lux, need %.0f) — "
                         "a shadow cannot be distinguished from the room",
                         d->baseline, d->cfg.min_baseline_lux);
                fault(d, msg);
            } else {
                d->state = LS_STATE_IDLE;
            }
        }
        return LS_GESTURE_NONE;
    }

    d->last_ratio = lux / d->baseline;

    int flipped = update_cover(d);

    /* Track slow ambient drift (sun moving, lights dimmed) but only while
     * idle and clearly uncovered, so a hand can never pull the baseline down
     * toward itself and disarm the detector. */
    if (d->state == LS_STATE_IDLE && !d->covered &&
        d->last_ratio > d->cfg.uncover_ratio) {
        double a = d->cfg.baseline_alpha;
        d->baseline = d->baseline * (1.0 - a) + lux * a;
    }

    int refractory = d->have_fired &&
                     (t_ms - d->t_last_gesture) < d->cfg.refractory_ms;

    ls_gesture out = LS_GESTURE_NONE;

    if (d->cfg.switch_mode) {
        /* Switch mode: the debounced cover flag IS the output. No windows to
         * wait out, so an edge fires the moment the debounce confirms it —
         * ~300 ms after the hand, which is as fast as this sensor can go.
         * The refractory window is not needed: the Schmitt gap plus debounce
         * already guarantee edges alternate cleanly. */
        if (flipped) {
            if (d->covered) {
                d->t_cover_start = t_ms;
                d->state = LS_STATE_COVERED;
                out = LS_GESTURE_ON;
            } else {
                d->t_release = t_ms;
                d->state = LS_STATE_IDLE;
                out = LS_GESTURE_OFF;
            }
        }
    } else switch (d->state) {
    case LS_STATE_IDLE:
        if (flipped && d->covered) {
            if (refractory) {
                /* Swallow the whole cover: entering during the refractory
                 * window must not queue up a gesture for when it expires. */
                d->state = LS_STATE_SPENT;
            } else {
                d->t_cover_start = t_ms;
                d->state = LS_STATE_COVERED;
            }
        }
        break;

    case LS_STATE_COVERED:
        if (!d->covered) {
            d->t_release = t_ms;
            if (d->cfg.double_gap_ms <= 0.0) {
                out = LS_GESTURE_TAP;      /* double-tap disabled: fire now */
                d->state = LS_STATE_IDLE;
            } else {
                d->state = LS_STATE_TAP_PENDING;
            }
        } else if (t_ms - d->t_cover_start >= d->cfg.hold_ms) {
            /* Fire as soon as the threshold is crossed rather than on
             * release, so a hold feels like a press and not a delay. */
            out = LS_GESTURE_HOLD;
            d->state = LS_STATE_SPENT;
        }
        break;

    case LS_STATE_TAP_PENDING:
        if (d->covered) {
            out = LS_GESTURE_DOUBLE_TAP;
            d->state = LS_STATE_SPENT;
        } else if (t_ms - d->t_release >= d->cfg.double_gap_ms) {
            out = LS_GESTURE_TAP;
            d->state = LS_STATE_IDLE;
        }
        break;

    case LS_STATE_SPENT:
        if (!d->covered)
            d->state = LS_STATE_IDLE;
        break;

    case LS_STATE_CALIBRATING:
    case LS_STATE_FAULT:
        break;
    }

    if (out != LS_GESTURE_NONE) {
        d->t_last_gesture = t_ms;
        d->have_fired = 1;
    }
    return out;
}

double      ls_detector_baseline(const ls_detector *d) { return d->baseline; }
double      ls_detector_ratio(const ls_detector *d)    { return d->last_ratio; }
ls_state    ls_detector_state(const ls_detector *d)    { return d->state; }
int         ls_detector_covered(const ls_detector *d)  { return d->covered; }
const char *ls_detector_fault(const ls_detector *d)    { return d->fault; }
