/* glow.h — what the overlay should look like right now.
 *
 * The overlay's whole personality — breathing when idle, brightening as the
 * shadow deepens, an arc filling toward the hold threshold, a pulse when a
 * gesture fires — is a pure function of a small snapshot and is unit-tested
 * on any machine. The AppKit layer that draws it is deliberately dumb: it
 * maps a frame to layer properties and owns nothing else. Same split as
 * ls_diag in ui.h.
 */
#ifndef LS_GLOW_H
#define LS_GLOW_H

#include "detector.h"

/* Animation constants, fixed here so tests can pin them. */
#define LS_GLOW_BREATH_MS   3000.0  /* idle breathing period                */
#define LS_GLOW_PULSE_MS     600.0  /* gesture pulse decay time             */
#define LS_GLOW_IDLE_FLOOR     0.10 /* idle breathing band                  */
#define LS_GLOW_IDLE_CEIL      0.35
/* The ring starts reacting at a 3% dip — the noise floor is ~0.075%, so an
 * approaching hand is visible long before the detector's own thresholds.
 * Feedback must lead the gesture, not confirm it. */
#define LS_GLOW_REACT_RATIO    0.97

/* POD snapshot; copies of this cross the poll-thread boundary, never
 * pointers into the detector. */
typedef struct {
    ls_state   state;
    double     ratio;          /* last_lux / baseline                       */
    double     cover_ratio;    /* detector thresholds, for the ramp         */
    double     uncover_ratio;
    double     hold_ms;        /* time a cover must last to become a hold   */
    double     t_now;          /* sample-clock ms                           */
    double     t_cover_start;  /* detector clock, peeked read-only          */
    double     t_last_gesture; /* when the loop last emitted a gesture      */
    int        have_fired;     /* 0 until the first gesture is emitted      */
    ls_gesture last_gesture;
} ls_glow_input;

typedef enum {
    LS_GLOW_CALIBRATING = 0,
    LS_GLOW_IDLE,
    LS_GLOW_COVERING,
    LS_GLOW_FIRED,
    LS_GLOW_FAULT
} ls_glow_mode;

typedef struct {
    ls_glow_mode mode;
    double intensity;  /* 0..1 how bright the ring is                       */
    double progress;   /* 0..1 arc toward the hold threshold                */
    double pulse;      /* 1 -> 0 decay after a gesture fires                */
} ls_glow_frame;

/* Raised cosine, 0 at t = 0, 1 at half period. Pure function of time so the
 * renderer and the tests agree on every frame. */
double ls_glow_breath(double t_ms);

/* Exponential approach of current toward target: the renderer's per-frame
 * smoothing, kept pure so its feel is pinned by tests. tau_ms is the time
 * constant; dt_ms <= 0 returns current, tau_ms <= 0 snaps to target. */
double ls_glow_approach(double current, double target, double dt_ms,
                        double tau_ms);

/* Every output is clamped to [0, 1] no matter what the input claims. */
void ls_glow_eval(const ls_glow_input *in, ls_glow_frame *out);

#endif /* LS_GLOW_H */
