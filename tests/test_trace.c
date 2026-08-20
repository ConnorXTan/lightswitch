/* test_trace.c — the recording format, and a full replay through the detector.
 *
 * The last test is the important one: it wires a committed fixture through the
 * exact sensor interface the live sensor implements, so the end-to-end path is
 * covered on machines that have no sensor at all. */
#include "detector.h"
#include "harness.h"
#include "sensor.h"
#include "trace.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void test_write_then_read(void)
{
    const char *path = "build/test_trace_tmp.lstrace";
    char err[192];

    ls_trace_writer *w = ls_trace_open_write(path, "unit test", err, sizeof(err));
    CHECK(w != NULL);
    if (!w)
        return;
    for (int i = 0; i < 5; i++)
        CHECK_EQ(ls_trace_write(w, i * 100.0, 4800.0 + i), 0);
    CHECK_EQ(ls_trace_close_write(w), 0);

    ls_trace_reader *r = ls_trace_open_read(path, err, sizeof(err));
    CHECK(r != NULL);
    if (!r)
        return;

    int n = 0;
    double t, lux;
    while (ls_trace_read(r, &t, &lux, err, sizeof(err)) == 1) {
        CHECK_NEAR(t, n * 100.0, 1e-6);
        CHECK_NEAR(lux, 4800.0 + n, 1e-6);
        n++;
    }
    CHECK_EQ(n, 5);
    ls_trace_close_read(r);
    unlink(path);
}

static void test_missing_file(void)
{
    char err[192];
    CHECK(ls_trace_open_read("build/no_such_trace.lstrace", err, sizeof(err)) == NULL);
    CHECK(strstr(err, "cannot read") != NULL);
}

static void test_malformed_line_is_reported(void)
{
    const char *path = "build/test_trace_bad.lstrace";
    char err[192];

    FILE *fp = fopen(path, "w");
    CHECK(fp != NULL);
    if (!fp)
        return;
    fputs("# lightswitch trace v1\n0 4800\nnot-a-number\n", fp);
    fclose(fp);

    ls_trace_reader *r = ls_trace_open_read(path, err, sizeof(err));
    CHECK(r != NULL);
    if (!r)
        return;

    double t, lux;
    CHECK_EQ(ls_trace_read(r, &t, &lux, err, sizeof(err)), 1);
    CHECK_EQ(ls_trace_read(r, &t, &lux, err, sizeof(err)), -1);
    CHECK(strstr(err, "line 3") != NULL);
    ls_trace_close_read(r);
    unlink(path);
}

/* Drive a committed fixture through the real sensor interface. */
static int replay_fixture(const char *path, ls_gesture *out, int max)
{
    char err[192];
    ls_sensor *s = ls_sensor_open_replay(path, 0, err, sizeof(err));
    if (!s) {
        fprintf(stderr, "    (could not open %s: %s)\n", path, err);
        return -1;
    }

    ls_detector_config cfg;
    ls_detector_config_defaults(&cfg);
    ls_detector d;
    ls_detector_init(&d, &cfg);

    int n = 0;
    double t, lux;
    while (ls_sensor_read(s, &t, &lux) == 1) {
        ls_gesture g = ls_detector_push(&d, t, lux);
        if (g != LS_GESTURE_NONE && n < max)
            out[n++] = g;
    }
    ls_sensor_close(s);
    return n;
}

static void test_replay_fixtures(void)
{
    ls_gesture got[16];
    int n;

    n = replay_fixture("tests/traces/idle.lstrace", got, 16);
    CHECK_EQ(n, 0);

    n = replay_fixture("tests/traces/tap.lstrace", got, 16);
    CHECK_EQ(n, 1);
    if (n == 1)
        CHECK_EQ(got[0], LS_GESTURE_TAP);

    n = replay_fixture("tests/traces/double_tap.lstrace", got, 16);
    CHECK_EQ(n, 1);
    if (n == 1)
        CHECK_EQ(got[0], LS_GESTURE_DOUBLE_TAP);

    n = replay_fixture("tests/traces/hold.lstrace", got, 16);
    CHECK_EQ(n, 1);
    if (n == 1)
        CHECK_EQ(got[0], LS_GESTURE_HOLD);

    n = replay_fixture("tests/traces/walk_past.lstrace", got, 16);
    CHECK_EQ(n, 0);
}

TEST_MAIN_BEGIN("trace")
    RUN(test_write_then_read);
    RUN(test_missing_file);
    RUN(test_malformed_line_is_reported);
    RUN(test_replay_fixtures);
TEST_MAIN_END()
