/* glow.c — the overlay's look as a pure function. See glow.h. */
#include "glow.h"

#include <math.h>

#ifndef M_PI /* not guaranteed by -std=c11; glibc hides it without XSI */
#define M_PI 3.14159265358979323846
#endif

static double clamp01(double v)
{
    if (!(v > 0.0))
        return 0.0;   /* catches NaN too */
    return v < 1.0 ? v : 1.0;
}

double ls_glow_breath(double t_ms)
{
    return 0.5 - 0.5 * cos(2.0 * M_PI * t_ms / LS_GLOW_BREATH_MS);
}

double ls_glow_approach(double current, double target, double dt_ms,
                        double tau_ms)
{
    if (dt_ms <= 0.0)
        return current;
    if (tau_ms <= 0.0)
        return target;
    return current + (target - current) * (1.0 - exp(-dt_ms / tau_ms));
}

/* How deep into the shadow the signal is: 0 where the ring starts reacting
 * (a 3% dip — far above the noise floor, far before the detector's own
 * thresholds), 1 at the cover threshold. Reacting this early is what makes
 * the ring feel attached to the hand instead of confirming the detector. */
static double cover_depth(const ls_glow_input *in)
{
    double start = LS_GLOW_REACT_RATIO;
    if (start <= in->cover_ratio)
        start = in->uncover_ratio;   /* unusual tuning; fall back to the band */
    double band = start - in->cover_ratio;
    if (band <= 0.0)
        return in->ratio < start ? 1.0 : 0.0;
    return clamp01((start - in->ratio) / band);
}

void ls_glow_eval(const ls_glow_input *in, ls_glow_frame *out)
{
    out->mode      = LS_GLOW_IDLE;
    out->intensity = 0.0;
    out->progress  = 0.0;
    out->pulse     = 0.0;

    if (!in)
        return;

    /* Pulse decays from the moment a gesture was emitted, regardless of what
     * the detector state has moved on to. */
    if (in->have_fired)
        out->pulse = clamp01(1.0 - (in->t_now - in->t_last_gesture) / LS_GLOW_PULSE_MS);

    /* Intensity: breathe in the idle band, then ramp toward full as the
     * shadow deepens through the Schmitt band. */
    double depth = cover_depth(in);
    if (depth <= 0.0) {
        out->intensity = LS_GLOW_IDLE_FLOOR +
            (LS_GLOW_IDLE_CEIL - LS_GLOW_IDLE_FLOOR) * ls_glow_breath(in->t_now);
    } else {
        out->intensity = LS_GLOW_IDLE_CEIL + (1.0 - LS_GLOW_IDLE_CEIL) * depth;
    }

    /* The arc fills only while an actual cover is running its hold timer. */
    if (in->state == LS_STATE_COVERED && in->hold_ms > 0.0)
        out->progress = clamp01((in->t_now - in->t_cover_start) / in->hold_ms);

    if (in->state == LS_STATE_FAULT) {
        out->mode      = LS_GLOW_FAULT;
        out->intensity = 0.8;
        out->progress  = 0.0;
        out->pulse     = 0.0;
    } else if (in->state == LS_STATE_CALIBRATING) {
        out->mode     = LS_GLOW_CALIBRATING;
        out->progress = 0.0;
        out->pulse    = 0.0;
    } else if (out->pulse > 0.0) {
        out->mode = LS_GLOW_FIRED;
    } else if (in->state == LS_STATE_COVERED) {
        out->mode = LS_GLOW_COVERING;
    }

    out->intensity = clamp01(out->intensity);
    out->progress  = clamp01(out->progress);
    out->pulse     = clamp01(out->pulse);
}
