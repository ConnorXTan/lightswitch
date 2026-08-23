/* test_glow.c — the overlay's look, checked without a screen.
 *
 * ls_glow_eval is a pure function of a snapshot, so every visual behaviour —
 * breathing, the cover ramp, the hold arc, the gesture pulse — is pinned
 * here and runs on any machine. */
#include "glow.h"
#include "harness.h"

/* A quiet, calibrated room with nothing happening. */
static ls_glow_input healthy(void)
{
    ls_glow_input in;
    in.state          = LS_STATE_IDLE;
    in.ratio          = 1.0;
    in.cover_ratio    = 0.45;
    in.uncover_ratio  = 0.75;
    in.hold_ms        = 1100.0;
    in.t_now          = 10000.0;
    in.t_cover_start  = 0.0;
    in.t_last_gesture = 0.0;
    in.have_fired     = 0;
    in.last_gesture   = LS_GESTURE_NONE;
    return in;
}

static void test_breath_is_deterministic(void)
{
    CHECK_NEAR(ls_glow_breath(0.0), 0.0, 1e-9);
    CHECK_NEAR(ls_glow_breath(LS_GLOW_BREATH_MS / 2.0), 1.0, 1e-9);
    CHECK_NEAR(ls_glow_breath(LS_GLOW_BREATH_MS), 0.0, 1e-9);
    CHECK_NEAR(ls_glow_breath(123.0),
               ls_glow_breath(123.0 + LS_GLOW_BREATH_MS), 1e-9);
}

static void test_calibrating_mode(void)
{
    ls_glow_input in = healthy();
    ls_glow_frame f;
    in.state = LS_STATE_CALIBRATING;
    ls_glow_eval(&in, &f);
    CHECK_EQ(f.mode, LS_GLOW_CALIBRATING);
    CHECK_NEAR(f.progress, 0.0, 1e-9);
    CHECK_NEAR(f.pulse, 0.0, 1e-9);
}

static void test_idle_breathes(void)
{
    ls_glow_input in = healthy();
    ls_glow_frame f;

    in.t_now = 0.0;
    ls_glow_eval(&in, &f);
    CHECK_EQ(f.mode, LS_GLOW_IDLE);
    CHECK_NEAR(f.intensity, LS_GLOW_IDLE_FLOOR, 1e-9);

    in.t_now = LS_GLOW_BREATH_MS / 2.0;
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.intensity, LS_GLOW_IDLE_CEIL, 1e-9);
}

static void test_cover_ramp(void)
{
    ls_glow_input in = healthy();
    ls_glow_frame f;
    in.state         = LS_STATE_COVERED;
    in.t_cover_start = in.t_now;

    in.ratio = LS_GLOW_REACT_RATIO - 1e-9;   /* shadow just forming */
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.intensity, LS_GLOW_IDLE_CEIL, 1e-6);

    in.ratio = in.cover_ratio;     /* fully covered */
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.intensity, 1.0, 1e-9);
    CHECK_EQ(f.mode, LS_GLOW_COVERING);

    double mid, deep;
    in.ratio = 0.60;
    ls_glow_eval(&in, &f);
    mid = f.intensity;
    in.ratio = 0.50;
    ls_glow_eval(&in, &f);
    deep = f.intensity;
    CHECK(mid > LS_GLOW_IDLE_CEIL && mid < 1.0);
    CHECK(deep > mid);             /* deeper shadow, brighter ring */
}

static void test_reacts_before_the_detector(void)
{
    /* The ring must visibly lead the gesture: a 10% dip is nowhere near the
     * detector's release threshold, but the ring is already well above its
     * idle band. Still IDLE — the detector has not seen anything yet. */
    ls_glow_input in = healthy();
    ls_glow_frame f;
    in.state = LS_STATE_IDLE;
    in.ratio = 0.90;
    ls_glow_eval(&in, &f);
    CHECK_EQ(f.mode, LS_GLOW_IDLE);
    CHECK(f.intensity > LS_GLOW_IDLE_CEIL);
}

static void test_approach(void)
{
    /* Converges monotonically, ~63% of the way after one time constant. */
    double v = ls_glow_approach(0.0, 1.0, 100.0, 100.0);
    CHECK_NEAR(v, 0.632, 0.001);
    CHECK(ls_glow_approach(v, 1.0, 100.0, 100.0) > v);

    CHECK_NEAR(ls_glow_approach(0.3, 1.0, 0.0, 100.0), 0.3, 1e-9);    /* no dt */
    CHECK_NEAR(ls_glow_approach(0.3, 1.0, 100.0, 0.0), 1.0, 1e-9);    /* snap  */
    CHECK_NEAR(ls_glow_approach(0.3, 1.0, 10000.0, 100.0), 1.0, 1e-6); /* long */
}

static void test_hold_progress(void)
{
    ls_glow_input in = healthy();
    ls_glow_frame f;
    in.state         = LS_STATE_COVERED;
    in.ratio         = 0.1;
    in.t_cover_start = 10000.0;

    in.t_now = 10000.0;
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.progress, 0.0, 1e-9);

    in.t_now = 10000.0 + in.hold_ms / 2.0;
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.progress, 0.5, 1e-9);

    in.t_now = 10000.0 + 2.0 * in.hold_ms;
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.progress, 1.0, 1e-9);
}

static void test_progress_only_while_covered(void)
{
    ls_glow_input in = healthy();
    ls_glow_frame f;
    in.t_cover_start = 9000.0;     /* stale cover clock */

    in.state = LS_STATE_IDLE;
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.progress, 0.0, 1e-9);

    in.state = LS_STATE_TAP_PENDING;
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.progress, 0.0, 1e-9);
}

static void test_pulse_decay(void)
{
    ls_glow_input in = healthy();
    ls_glow_frame f;
    in.have_fired     = 1;
    in.last_gesture   = LS_GESTURE_TAP;
    in.t_last_gesture = in.t_now;

    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.pulse, 1.0, 1e-9);
    CHECK_EQ(f.mode, LS_GLOW_FIRED);

    in.t_now = in.t_last_gesture + LS_GLOW_PULSE_MS / 2.0;
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.pulse, 0.5, 1e-9);

    in.t_now = in.t_last_gesture + LS_GLOW_PULSE_MS;
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.pulse, 0.0, 1e-9);
    CHECK_EQ(f.mode, LS_GLOW_IDLE); /* pulse over, mode falls back */
}

static void test_pulse_needs_a_real_gesture(void)
{
    /* t_last_gesture is zero-initialised; shortly after start that is only
     * LS_GLOW_PULSE_MS in the past. Without the have_fired gate the overlay
     * would boot up mid-pulse. */
    ls_glow_input in = healthy();
    ls_glow_frame f;
    in.t_now          = 100.0;
    in.t_last_gesture = 0.0;
    in.have_fired     = 0;
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.pulse, 0.0, 1e-9);
    CHECK_EQ(f.mode, LS_GLOW_IDLE);
}

static void test_fault_mode_wins(void)
{
    ls_glow_input in = healthy();
    ls_glow_frame f;
    in.state          = LS_STATE_FAULT;
    in.have_fired     = 1;
    in.t_last_gesture = in.t_now;  /* pulse would otherwise be 1 */
    ls_glow_eval(&in, &f);
    CHECK_EQ(f.mode, LS_GLOW_FAULT);
    CHECK_NEAR(f.pulse, 0.0, 1e-9);
}

static void test_outputs_clamped(void)
{
    ls_glow_input in = healthy();
    ls_glow_frame f;

    in.ratio = -5.0;               /* sensor said something absurd */
    ls_glow_eval(&in, &f);
    CHECK(f.intensity >= 0.0 && f.intensity <= 1.0);

    in.ratio = 5.0;
    ls_glow_eval(&in, &f);
    CHECK(f.intensity >= 0.0 && f.intensity <= 1.0);

    in = healthy();
    in.state         = LS_STATE_COVERED;
    in.t_cover_start = in.t_now + 1000.0;  /* clock from the future */
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.progress, 0.0, 1e-9);

    in = healthy();
    in.uncover_ratio = in.cover_ratio;     /* degenerate band: no divide */
    in.ratio         = 0.1;
    ls_glow_eval(&in, &f);
    CHECK_NEAR(f.intensity, 1.0, 1e-9);
}

TEST_MAIN_BEGIN("glow")
    RUN(test_breath_is_deterministic);
    RUN(test_calibrating_mode);
    RUN(test_idle_breathes);
    RUN(test_cover_ramp);
    RUN(test_reacts_before_the_detector);
    RUN(test_approach);
    RUN(test_hold_progress);
    RUN(test_progress_only_while_covered);
    RUN(test_pulse_decay);
    RUN(test_pulse_needs_a_real_gesture);
    RUN(test_fault_mode_wins);
    RUN(test_outputs_clamped);
TEST_MAIN_END()
