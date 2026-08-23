/* test_detector.c — the gesture engine, exercised with synthetic signals.
 *
 * These tests are the reason the detector has no platform dependencies: the
 * whole recognition path runs here in milliseconds, on any machine, with the
 * awkward cases (drift, dropouts, noise) reproduced exactly every run.
 */
#include "detector.h"
#include "harness.h"

#include <string.h>

#define STEP_MS 100.0     /* the sampling cadence lightswitch actually uses */
#define BASELINE 4830.0   /* measured office baseline, see docs/SIGNAL.md   */
#define NOISE_FRAC 0.0012 /* measured 1-sigma noise, 0.12% of baseline      */

typedef struct {
    ls_detector d;
    double      t;
    double      step;
    double      baseline;
    unsigned    seed;
    ls_gesture  events[64];
    int         nevents;
} rig;

/* A fixed-seed LCG keeps every run byte-identical, so a failure reproduces. */
static double rig_noise(rig *r)
{
    r->seed = r->seed * 1103515245u + 12345u;
    double u = (double)((r->seed >> 16) & 0x7fff) / 32767.0;
    return u * 2.0 - 1.0;
}

static void rig_init(rig *r, const ls_detector_config *cfg, double baseline)
{
    memset(r, 0, sizeof(*r));
    r->step     = STEP_MS;
    r->baseline = baseline;
    r->seed     = 12345u;
    ls_detector_init(&r->d, cfg);
}

static void rig_samples(rig *r, int n, double ratio)
{
    for (int i = 0; i < n; i++) {
        double lux = r->baseline * ratio + rig_noise(r) * r->baseline * NOISE_FRAC;
        if (lux < 0.0)
            lux = 0.0;
        ls_gesture g = ls_detector_push(&r->d, r->t, lux);
        if (g != LS_GESTURE_NONE && r->nevents < 64)
            r->events[r->nevents++] = g;
        r->t += r->step;
    }
}

static void rig_ms(rig *r, double ms, double ratio)
{
    rig_samples(r, (int)(ms / STEP_MS + 0.5), ratio);
}

/* Every test starts from an armed detector. */
static void rig_calibrate(rig *r)
{
    rig_ms(r, r->d.cfg.calibration_ms + 200.0, 1.0);
}

static ls_detector_config base_config(void)
{
    ls_detector_config cfg;
    ls_detector_config_defaults(&cfg);
    return cfg;
}

/* ------------------------------------------------------------------ */

static void test_calibration_establishes_baseline(void)
{
    ls_detector_config cfg = base_config();
    rig r;
    rig_init(&r, &cfg, BASELINE);

    rig_ms(&r, 1000.0, 1.0);
    CHECK_EQ(ls_detector_state(&r.d), LS_STATE_CALIBRATING);

    rig_ms(&r, 1500.0, 1.0);
    CHECK_EQ(ls_detector_state(&r.d), LS_STATE_IDLE);
    CHECK_NEAR(ls_detector_baseline(&r.d), BASELINE, BASELINE * 0.01);
    CHECK_EQ(r.nevents, 0);
}

static void test_dark_room_faults_instead_of_arming(void)
{
    ls_detector_config cfg = base_config();
    rig r;
    rig_init(&r, &cfg, 8.0); /* well below min_baseline_lux */

    rig_calibrate(&r);
    CHECK_EQ(ls_detector_state(&r.d), LS_STATE_FAULT);
    CHECK(strlen(ls_detector_fault(&r.d)) > 0);

    /* A faulted detector must stay inert rather than emitting nonsense. */
    rig_ms(&r, 5000.0, 0.02);
    CHECK_EQ(r.nevents, 0);
}

static void test_idle_noise_produces_no_gestures(void)
{
    ls_detector_config cfg = base_config();
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    rig_ms(&r, 60000.0, 1.0); /* a minute of undisturbed room */
    CHECK_EQ(r.nevents, 0);
    CHECK_EQ(ls_detector_state(&r.d), LS_STATE_IDLE);
}

static void test_single_cover_emits_tap(void)
{
    ls_detector_config cfg = base_config();
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    rig_ms(&r, 500.0, 0.02);
    CHECK_EQ(r.nevents, 0); /* nothing yet: could still become a double-tap */

    rig_ms(&r, 1500.0, 1.0);
    CHECK_EQ(r.nevents, 1);
    CHECK_EQ(r.events[0], LS_GESTURE_TAP);
    CHECK_EQ(ls_detector_state(&r.d), LS_STATE_IDLE);
}

static void test_two_covers_emit_double_tap(void)
{
    ls_detector_config cfg = base_config();
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    rig_ms(&r, 500.0, 0.02);
    rig_ms(&r, 400.0, 1.0);
    rig_ms(&r, 500.0, 0.02);
    rig_ms(&r, 1500.0, 1.0);

    CHECK_EQ(r.nevents, 1);
    CHECK_EQ(r.events[0], LS_GESTURE_DOUBLE_TAP);
}

static void test_long_cover_emits_exactly_one_hold(void)
{
    ls_detector_config cfg = base_config();
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    rig_ms(&r, 4000.0, 0.02); /* far longer than hold_ms */
    CHECK_EQ(r.nevents, 1);
    CHECK_EQ(r.events[0], LS_GESTURE_HOLD);

    /* Releasing must not add a trailing tap. */
    rig_ms(&r, 1500.0, 1.0);
    CHECK_EQ(r.nevents, 1);
}

static void test_hold_fires_while_still_covered(void)
{
    ls_detector_config cfg = base_config();
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    /* hold_ms is 1100; by 1600ms of cover the gesture should already be out,
     * without waiting for the hand to lift. */
    rig_ms(&r, 1600.0, 0.02);
    CHECK_EQ(r.nevents, 1);
    CHECK_EQ(r.events[0], LS_GESTURE_HOLD);
    CHECK(ls_detector_covered(&r.d));
}

static void test_shallow_dip_is_ignored(void)
{
    ls_detector_config cfg = base_config();
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    /* Someone walking past, or a cloud: a 20% dip is not an occlusion. */
    rig_ms(&r, 3000.0, 0.80);
    rig_ms(&r, 1000.0, 1.0);
    CHECK_EQ(r.nevents, 0);
}

static void test_single_sample_dropout_is_debounced(void)
{
    ls_detector_config cfg = base_config();
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    /* One isolated dark sample, repeatedly. debounce_samples=2 must eat it. */
    for (int i = 0; i < 20; i++) {
        rig_samples(&r, 1, 0.01);
        rig_samples(&r, 6, 1.0);
    }
    CHECK_EQ(r.nevents, 0);
}

static void test_negative_readings_are_skipped(void)
{
    ls_detector_config cfg = base_config();
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    /* A dropped read is not darkness; it must not advance the cover state. */
    for (int i = 0; i < 40; i++) {
        ls_gesture g = ls_detector_push(&r.d, r.t, -1.0);
        CHECK_EQ(g, LS_GESTURE_NONE);
        r.t += STEP_MS;
    }
    CHECK_EQ(ls_detector_state(&r.d), LS_STATE_IDLE);
    CHECK_EQ(r.nevents, 0);
}

static void test_slow_ambient_drift_is_tracked(void)
{
    ls_detector_config cfg = base_config();
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    /* Daylight fading: 4830 -> 2400 lux over five minutes. The baseline must
     * follow without ever crossing the cover threshold. */
    const int steps = 3000; /* 300s at 10 Hz */
    for (int i = 0; i < steps; i++) {
        double frac = (double)i / (double)steps;
        r.baseline = BASELINE + (2400.0 - BASELINE) * frac;
        rig_samples(&r, 1, 1.0);
    }
    CHECK_EQ(r.nevents, 0);
    CHECK_NEAR(ls_detector_baseline(&r.d), 2400.0, 250.0);

    /* And it must still detect a real gesture at the new light level. */
    rig_ms(&r, 500.0, 0.02);
    rig_ms(&r, 1500.0, 1.0);
    CHECK_EQ(r.nevents, 1);
    CHECK_EQ(r.events[0], LS_GESTURE_TAP);
}

static void test_covered_hand_does_not_poison_baseline(void)
{
    ls_detector_config cfg = base_config();
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    double before = ls_detector_baseline(&r.d);
    rig_ms(&r, 10000.0, 0.02); /* ten seconds of hand */
    CHECK_NEAR(ls_detector_baseline(&r.d), before, before * 0.02);
}

static void test_refractory_window_suppresses_repeats(void)
{
    ls_detector_config cfg = base_config();
    cfg.refractory_ms = 3000.0;
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    rig_ms(&r, 1600.0, 0.02); /* hold */
    CHECK_EQ(r.nevents, 1);

    rig_ms(&r, 400.0, 1.0);
    rig_ms(&r, 500.0, 0.02);  /* immediate second gesture, inside the window */
    rig_ms(&r, 1500.0, 1.0);
    CHECK_EQ(r.nevents, 1);

    /* Once the window has passed, gestures work again. */
    rig_ms(&r, 3000.0, 1.0);
    rig_ms(&r, 500.0, 0.02);
    rig_ms(&r, 1500.0, 1.0);
    CHECK_EQ(r.nevents, 2);
    CHECK_EQ(r.events[1], LS_GESTURE_TAP);
}

static void test_zero_gap_taps_fire_immediately(void)
{
    ls_detector_config cfg = base_config();
    cfg.double_gap_ms = 0.0; /* trade double-tap away for latency */
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    rig_ms(&r, 500.0, 0.02);
    rig_samples(&r, 3, 1.0); /* just enough to debounce the release */
    CHECK_EQ(r.nevents, 1);
    CHECK_EQ(r.events[0], LS_GESTURE_TAP);
}

static void test_config_validation_rejects_bad_values(void)
{
    char err[128];
    ls_detector_config cfg;

    cfg = base_config();
    CHECK_EQ(ls_detector_config_validate(&cfg, err, sizeof(err)), 0);

    cfg = base_config();
    cfg.cover_ratio = 0.9; /* above uncover_ratio: would chatter */
    CHECK_EQ(ls_detector_config_validate(&cfg, err, sizeof(err)), -1);

    cfg = base_config();
    cfg.double_gap_ms = 2000.0; /* above hold_ms: a hold could never resolve */
    CHECK_EQ(ls_detector_config_validate(&cfg, err, sizeof(err)), -1);

    cfg = base_config();
    cfg.debounce_samples = 0;
    CHECK_EQ(ls_detector_config_validate(&cfg, err, sizeof(err)), -1);

    cfg = base_config();
    cfg.baseline_alpha = 1.0;
    CHECK_EQ(ls_detector_config_validate(&cfg, err, sizeof(err)), -1);
}

static void test_gesture_names_are_stable(void)
{
    CHECK_STR(ls_gesture_name(LS_GESTURE_TAP), "tap");
    CHECK_STR(ls_gesture_name(LS_GESTURE_DOUBLE_TAP), "double-tap");
    CHECK_STR(ls_gesture_name(LS_GESTURE_HOLD), "hold");
    CHECK_STR(ls_gesture_name(LS_GESTURE_ON), "on");
    CHECK_STR(ls_gesture_name(LS_GESTURE_OFF), "off");
    CHECK_STR(ls_gesture_name(LS_GESTURE_NONE), "none");
}

/* ---- switch mode: cover/uncover as a plain on/off switch ----------- */

static void test_switch_mode_emits_on_off(void)
{
    ls_detector_config cfg = base_config();
    cfg.switch_mode = 1;
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    rig_ms(&r, 1000.0, 0.02);
    CHECK_EQ(r.nevents, 1);
    CHECK_EQ(r.events[0], LS_GESTURE_ON);
    CHECK_EQ(ls_detector_state(&r.d), LS_STATE_COVERED);

    rig_ms(&r, 1000.0, 1.0);
    CHECK_EQ(r.nevents, 2);
    CHECK_EQ(r.events[1], LS_GESTURE_OFF);
    CHECK_EQ(ls_detector_state(&r.d), LS_STATE_IDLE);
}

static void test_switch_mode_fires_at_the_debounce_limit(void)
{
    /* ON must appear after exactly debounce_samples covered samples — no
     * hold timer, no double-tap window, nothing else to wait for. */
    ls_detector_config cfg = base_config();
    cfg.switch_mode = 1;
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    rig_samples(&r, cfg.debounce_samples - 1, 0.02);
    CHECK_EQ(r.nevents, 0);
    rig_samples(&r, 1, 0.02);
    CHECK_EQ(r.nevents, 1);
    CHECK_EQ(r.events[0], LS_GESTURE_ON);
}

static void test_switch_mode_never_emits_fsm_gestures(void)
{
    /* A choreography that would produce a tap, a double-tap, and a hold in
     * the normal mode reduces to clean ON/OFF pairs. */
    ls_detector_config cfg = base_config();
    cfg.switch_mode = 1;
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    rig_ms(&r, 500.0, 0.02);   rig_ms(&r, 1500.0, 1.0);   /* would be tap  */
    rig_ms(&r, 450.0, 0.02);   rig_ms(&r, 300.0, 1.0);    /* would be dbl  */
    rig_ms(&r, 450.0, 0.02);   rig_ms(&r, 1500.0, 1.0);
    rig_ms(&r, 2000.0, 0.02);  rig_ms(&r, 1000.0, 1.0);   /* would be hold */

    CHECK_EQ(r.nevents, 8);
    for (int i = 0; i < r.nevents; i++)
        CHECK_EQ(r.events[i], (i % 2 == 0) ? LS_GESTURE_ON : LS_GESTURE_OFF);
}

static void test_switch_mode_ignores_shallow_dips(void)
{
    /* Someone walking past dims the room well below the release threshold
     * but not below the cover threshold: still not a press. */
    ls_detector_config cfg = base_config();
    cfg.switch_mode = 1;
    rig r;
    rig_init(&r, &cfg, BASELINE);
    rig_calibrate(&r);

    rig_ms(&r, 1200.0, 0.60);
    rig_ms(&r, 1000.0, 1.0);
    CHECK_EQ(r.nevents, 0);
}

TEST_MAIN_BEGIN("detector")
    RUN(test_calibration_establishes_baseline);
    RUN(test_dark_room_faults_instead_of_arming);
    RUN(test_idle_noise_produces_no_gestures);
    RUN(test_single_cover_emits_tap);
    RUN(test_two_covers_emit_double_tap);
    RUN(test_long_cover_emits_exactly_one_hold);
    RUN(test_hold_fires_while_still_covered);
    RUN(test_shallow_dip_is_ignored);
    RUN(test_single_sample_dropout_is_debounced);
    RUN(test_negative_readings_are_skipped);
    RUN(test_slow_ambient_drift_is_tracked);
    RUN(test_covered_hand_does_not_poison_baseline);
    RUN(test_refractory_window_suppresses_repeats);
    RUN(test_zero_gap_taps_fire_immediately);
    RUN(test_config_validation_rejects_bad_values);
    RUN(test_gesture_names_are_stable);
    RUN(test_switch_mode_emits_on_off);
    RUN(test_switch_mode_fires_at_the_debounce_limit);
    RUN(test_switch_mode_never_emits_fsm_gestures);
    RUN(test_switch_mode_ignores_shallow_dips);
TEST_MAIN_END()
