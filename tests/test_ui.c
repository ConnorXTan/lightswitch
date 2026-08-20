/* test_ui.c — the diagnosis logic behind the live view.
 *
 * Only ls_diag is tested, and that is the point of the split: deciding *why*
 * a gesture is not being recognised is real logic and gets covered here, while
 * the drawing code it feeds is dumb enough not to need it.
 *
 * Every case below is a signal that was actually observed on hardware. */
#include "harness.h"
#include "ui.h"

#include <string.h>

/* A healthy bright room: cover at 45% of baseline, release at 75%, sitting
 * comfortably uncovered. */
static ls_diag_input healthy(void)
{
    ls_diag_input in;
    in.state            = LS_STATE_IDLE;
    in.baseline         = 6200.0;
    in.ratio            = 1.0;
    in.cover_ratio      = 0.45;
    in.uncover_ratio    = 0.75;
    in.below_release_ms = 0.0;
    in.latched_ms       = 150.0;
    return in;
}

static void test_healthy_signal_is_silent(void)
{
    ls_diag_input in = healthy();
    char msg[512];
    CHECK_EQ(ls_diag(&in, msg, sizeof msg), LS_DIAG_OK);
    CHECK_EQ(strlen(msg), 0);
}

static void test_calibrating_never_warns(void)
{
    /* Nothing is meaningful before there is a baseline, so the view must not
     * accuse the room of being broken during the first two seconds. */
    ls_diag_input in = healthy();
    in.state            = LS_STATE_CALIBRATING;
    in.baseline         = 40.0;
    in.ratio            = 0.6;
    in.below_release_ms = 9000.0;
    in.latched_ms       = 9000.0;

    char msg[512];
    CHECK_EQ(ls_diag(&in, msg, sizeof msg), LS_DIAG_OK);
}

/* The failure this whole module exists for: 38 lux against a 66 lux baseline,
 * with cover at 30 and release at 50. Too dark to release, too bright to
 * cover, so the state machine can never complete another gesture. */
static void test_dead_zone_is_reported(void)
{
    ls_diag_input in = healthy();
    in.state            = LS_STATE_SPENT;
    in.baseline         = 66.0;
    in.ratio            = 38.0 / 66.0;
    in.below_release_ms = 8000.0;

    char msg[512];
    CHECK_EQ(ls_diag(&in, msg, sizeof msg), LS_DIAG_WARN);
    CHECK(strstr(msg, "between the thresholds") != NULL);
    CHECK(strstr(msg, "auto-brightness") != NULL);
}

static void test_dead_zone_needs_persistence(void)
{
    /* Passing through the dead zone is what every normal gesture does. Only
     * staying there is a fault. */
    ls_diag_input in = healthy();
    in.state            = LS_STATE_IDLE;
    in.ratio            = 0.6;
    in.below_release_ms = 400.0;

    char msg[512];
    CHECK(ls_diag(&in, msg, sizeof msg) != LS_DIAG_WARN);
}

static void test_deep_cover_is_not_a_dead_zone(void)
{
    /* Fully covered and holding is not a stall, however long it lasts. */
    ls_diag_input in = healthy();
    in.state            = LS_STATE_COVERED;
    in.ratio            = 0.05;
    in.below_release_ms = 8000.0;
    in.latched_ms       = 150.0;

    char msg[512];
    CHECK(ls_diag(&in, msg, sizeof msg) != LS_DIAG_WARN);
}

static void test_latched_sensor_is_reported(void)
{
    ls_diag_input in = healthy();
    in.latched_ms = 4000.0;

    char msg[512];
    CHECK_EQ(ls_diag(&in, msg, sizeof msg), LS_DIAG_WARN);
    CHECK(strstr(msg, "same reading") != NULL);
}

static void test_dead_zone_outranks_latching(void)
{
    /* A dim room latches constantly; that must not bury the more actionable
     * message when both are true. */
    ls_diag_input in = healthy();
    in.state            = LS_STATE_SPENT;
    in.baseline         = 66.0;
    in.ratio            = 0.58;
    in.below_release_ms = 8000.0;
    in.latched_ms       = 8000.0;

    char msg[512];
    CHECK_EQ(ls_diag(&in, msg, sizeof msg), LS_DIAG_WARN);
    CHECK(strstr(msg, "between the thresholds") != NULL);
}

static void test_spent_awaiting_release_is_a_note(void)
{
    ls_diag_input in = healthy();
    in.state            = LS_STATE_SPENT;
    in.ratio            = 0.1;
    in.below_release_ms = 7000.0;

    char msg[512];
    CHECK_EQ(ls_diag(&in, msg, sizeof msg), LS_DIAG_NOTE);
    CHECK(strstr(msg, "re-arm") != NULL);
}

static void test_dim_room_is_a_note_not_a_warning(void)
{
    /* 66 lux clears the 25 lux hard floor, so the app runs — but the usable
     * window is 20 lux and the user deserves to know before they conclude the
     * detector is broken. */
    ls_diag_input in = healthy();
    in.baseline = 66.0;

    char msg[512];
    CHECK_EQ(ls_diag(&in, msg, sizeof msg), LS_DIAG_NOTE);
    CHECK(strstr(msg, "baseline is only 66 lux") != NULL);
    CHECK(strstr(msg, "30") != NULL);   /* cover  = 66 * 0.45 */
    CHECK(strstr(msg, "50") != NULL);   /* release = 66 * 0.75 */
}

static void test_bright_room_is_not_flagged_dim(void)
{
    ls_diag_input in = healthy();
    in.baseline = 400.0;

    char msg[512];
    CHECK_EQ(ls_diag(&in, msg, sizeof msg), LS_DIAG_OK);
}

static void test_null_and_tiny_buffers_are_safe(void)
{
    ls_diag_input in = healthy();
    char msg[512];
    CHECK_EQ(ls_diag(NULL, msg, sizeof msg), LS_DIAG_OK);
    CHECK_EQ(ls_diag(&in, NULL, 16), LS_DIAG_OK);
    CHECK_EQ(ls_diag(&in, msg, 0), LS_DIAG_OK);

    /* Truncation must not overrun: a one-byte buffer still gets a terminator. */
    in.baseline = 66.0;
    char tiny[1];
    ls_diag(&in, tiny, sizeof tiny);
    CHECK_EQ(tiny[0], 0);
}

TEST_MAIN_BEGIN("ui")
    RUN(test_healthy_signal_is_silent);
    RUN(test_calibrating_never_warns);
    RUN(test_dead_zone_is_reported);
    RUN(test_dead_zone_needs_persistence);
    RUN(test_deep_cover_is_not_a_dead_zone);
    RUN(test_latched_sensor_is_reported);
    RUN(test_dead_zone_outranks_latching);
    RUN(test_spent_awaiting_release_is_a_note);
    RUN(test_dim_room_is_a_note_not_a_warning);
    RUN(test_bright_room_is_not_flagged_dim);
    RUN(test_null_and_tiny_buffers_are_safe);
TEST_MAIN_END()
