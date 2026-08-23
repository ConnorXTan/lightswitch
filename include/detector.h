/* detector.h — pure gesture recognition over an ambient-light signal.
 *
 * Nothing in this module touches the operating system. It consumes
 * (timestamp, lux) samples and emits gestures, which is what lets the
 * interesting half of lightswitch be unit-tested on any machine — including
 * CI runners that have no ambient light sensor and no macOS.
 *
 * Signal model (see docs/SIGNAL.md for the measurements behind it):
 *   - The sensor reports absolute lux, so every threshold is expressed as a
 *     fraction of a running baseline rather than an absolute level.
 *   - Occluding the sensor is a very large signal (~100% drop) against a very
 *     small noise floor (~0.12%), so the detection problem is not sensitivity;
 *     it is rejecting slow ambient drift and single-sample dropouts.
 */
#ifndef LS_DETECTOR_H
#define LS_DETECTOR_H

#include <stddef.h>

typedef enum {
    LS_GESTURE_NONE = 0,
    LS_GESTURE_TAP,
    LS_GESTURE_DOUBLE_TAP,
    LS_GESTURE_HOLD,
    LS_GESTURE_ON,       /* switch mode only: cover confirmed   */
    LS_GESTURE_OFF       /* switch mode only: release confirmed */
} ls_gesture;

const char *ls_gesture_name(ls_gesture g);

typedef struct {
    double calibration_ms;   /* how long to average before arming            */
    double min_baseline_lux; /* refuse to run in a room this dark            */
    double cover_ratio;      /* enter "covered" below this fraction of base  */
    double uncover_ratio;    /* leave "covered" above this fraction of base  */
    int    debounce_samples; /* agreeing samples required to flip cover state*/
    double hold_ms;          /* covered at least this long => HOLD           */
    double double_gap_ms;    /* second cover within this of release => DOUBLE*/
    double refractory_ms;    /* ignore new gestures this long after emitting */
    double baseline_alpha;   /* EMA weight for ambient drift, uncovered only */
    int    switch_mode;      /* 1: emit ON/OFF at the cover edges and skip
                                the tap/double-tap/hold machine entirely —
                                the fastest response the sensor can give     */
} ls_detector_config;

void ls_detector_config_defaults(ls_detector_config *cfg);

/* Returns 0 if the configuration is self-consistent, -1 otherwise with a
 * human-readable reason written to err. */
int ls_detector_config_validate(const ls_detector_config *cfg,
                                char *err, size_t errlen);

typedef enum {
    LS_STATE_CALIBRATING = 0, /* averaging the ambient baseline              */
    LS_STATE_IDLE,            /* armed, sensor uncovered                     */
    LS_STATE_COVERED,         /* cover confirmed, deciding tap vs hold       */
    LS_STATE_TAP_PENDING,     /* released early, waiting out the double gap  */
    LS_STATE_SPENT,           /* gesture emitted, waiting for release        */
    LS_STATE_FAULT            /* unusable (e.g. room too dark)               */
} ls_state;

const char *ls_state_name(ls_state s);

typedef struct {
    ls_detector_config cfg;
    ls_state state;

    double baseline;        /* current ambient reference, lux               */
    double last_lux;
    double last_ratio;      /* last_lux / baseline                          */

    double calib_sum;       /* calibration accumulator                      */
    long   calib_n;
    double t_first;
    double t_last;

    int    covered;         /* debounced cover flag                         */
    int    streak;          /* samples agreeing with a pending flip         */
    int    streak_target;

    double t_cover_start;
    double t_release;
    double t_last_gesture;
    int    have_fired;

    char   fault[160];
} ls_detector;

void ls_detector_init(ls_detector *d, const ls_detector_config *cfg);

/* Feed one sample. Timestamps are milliseconds on any monotonic scale.
 * A negative lux means "the sensor dropped this read" and is ignored.
 * Returns the gesture completed by this sample, or LS_GESTURE_NONE.
 * At most one gesture is emitted per sample. */
ls_gesture ls_detector_push(ls_detector *d, double t_ms, double lux);

double      ls_detector_baseline(const ls_detector *d);
double      ls_detector_ratio(const ls_detector *d);
ls_state    ls_detector_state(const ls_detector *d);
int         ls_detector_covered(const ls_detector *d);
const char *ls_detector_fault(const ls_detector *d);

#endif /* LS_DETECTOR_H */
