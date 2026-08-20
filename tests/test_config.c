/* test_config.c — config file and CLI settings share one code path, so this
 * covers both surfaces at once. */
#include "config.h"
#include "harness.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void test_defaults_are_valid(void)
{
    ls_config c;
    char err[192];
    ls_config_defaults(&c);

    CHECK_EQ(ls_detector_config_validate(&c.detector, err, sizeof(err)), 0);
    CHECK_EQ(c.on_tap.kind, LS_ACTION_NONE);
    CHECK_EQ(ls_config_has_bindings(&c), 0);
    CHECK_NEAR(c.poll_ms, 100.0, 1e-9);
}

static void test_set_numeric_settings(void)
{
    ls_config c;
    char err[192];
    ls_config_defaults(&c);

    CHECK_EQ(ls_config_set(&c, "cover_ratio", "0.35", err, sizeof(err)), 0);
    CHECK_NEAR(c.detector.cover_ratio, 0.35, 1e-9);

    CHECK_EQ(ls_config_set(&c, "debounce_samples", "3", err, sizeof(err)), 0);
    CHECK_EQ(c.detector.debounce_samples, 3);

    CHECK_EQ(ls_config_set(&c, "hold_ms", "1200", err, sizeof(err)), 0);
    CHECK_NEAR(c.detector.hold_ms, 1200.0, 1e-9);
}

static void test_rejects_bad_input(void)
{
    ls_config c;
    char err[192];
    ls_config_defaults(&c);

    CHECK_EQ(ls_config_set(&c, "cover_ratio", "banana", err, sizeof(err)), -1);
    CHECK(strstr(err, "cover_ratio") != NULL);

    CHECK_EQ(ls_config_set(&c, "debounce_samples", "2.5", err, sizeof(err)), -1);
    CHECK_EQ(ls_config_set(&c, "no_such_setting", "1", err, sizeof(err)), -1);
    CHECK(strstr(err, "unknown setting") != NULL);
}

static void test_assignment_form(void)
{
    ls_config c;
    char err[192];
    ls_config_defaults(&c);

    CHECK_EQ(ls_config_set_assignment(&c, "hold_ms=750", err, sizeof(err)), 0);
    CHECK_NEAR(c.detector.hold_ms, 750.0, 1e-9);

    /* Whitespace around the equals sign is normal in a config file. */
    CHECK_EQ(ls_config_set_assignment(&c, "cover_ratio = 0.4", err, sizeof(err)), 0);
    CHECK_NEAR(c.detector.cover_ratio, 0.4, 1e-9);

    CHECK_EQ(ls_config_set_assignment(&c, "no_equals_here", err, sizeof(err)), -1);
}

static void test_action_settings(void)
{
    ls_config c;
    char err[192];
    ls_config_defaults(&c);

    CHECK_EQ(ls_config_set(&c, "on_tap", "key:cmd+w", err, sizeof(err)), 0);
    CHECK_EQ(c.on_tap.kind, LS_ACTION_KEY);
    CHECK_EQ(ls_config_has_bindings(&c), 1);

    CHECK_EQ(ls_config_set(&c, "on_hold", "exec:say hello", err, sizeof(err)), 0);
    CHECK_EQ(c.on_hold.kind, LS_ACTION_EXEC);
    CHECK_STR(c.on_hold.command, "say hello");

    CHECK_EQ(ls_config_set(&c, "on_double_tap", "nonsense:x", err, sizeof(err)), -1);
}

static void write_temp(const char *path, const char *body)
{
    FILE *fp = fopen(path, "w");
    CHECK(fp != NULL); /* otherwise the real failure hides behind a load error */
    if (fp) {
        fputs(body, fp);
        fclose(fp);
    }
}

static void test_load_file(void)
{
    const char *path = "build/test_config_tmp.conf";
    char err[256];
    ls_config c;
    ls_config_defaults(&c);

    write_temp(path,
               "# lightswitch config\n"
               "\n"
               "  on_tap = key:cmd+w\n"
               "on_hold=exec:pmset displaysleepnow\n"
               "cover_ratio = 0.4\n"
               "debounce_samples = 3\n");

    CHECK_EQ(ls_config_load_file(&c, path, err, sizeof(err)), 1);
    CHECK_EQ(c.on_tap.kind, LS_ACTION_KEY);
    CHECK_EQ(c.on_tap.keycode, 13); /* w */
    CHECK_EQ(c.on_hold.kind, LS_ACTION_EXEC);
    CHECK_STR(c.on_hold.command, "pmset displaysleepnow");
    CHECK_NEAR(c.detector.cover_ratio, 0.4, 1e-9);
    CHECK_EQ(c.detector.debounce_samples, 3);
    unlink(path);
}

static void test_missing_file_is_not_an_error(void)
{
    ls_config c;
    char err[256];
    ls_config_defaults(&c);
    CHECK_EQ(ls_config_load_file(&c, "build/definitely_not_here.conf",
                                 err, sizeof(err)), 0);
}

static void test_bad_file_reports_line_number(void)
{
    const char *path = "build/test_config_bad.conf";
    char err[256];
    ls_config c;
    ls_config_defaults(&c);

    write_temp(path, "cover_ratio = 0.4\nbogus_key = 3\n");
    CHECK_EQ(ls_config_load_file(&c, path, err, sizeof(err)), -1);
    CHECK(strstr(err, ":2:") != NULL);
    unlink(path);
}

TEST_MAIN_BEGIN("config")
    RUN(test_defaults_are_valid);
    RUN(test_set_numeric_settings);
    RUN(test_rejects_bad_input);
    RUN(test_assignment_form);
    RUN(test_action_settings);
    RUN(test_load_file);
    RUN(test_missing_file_is_not_an_error);
    RUN(test_bad_file_reports_line_number);
TEST_MAIN_END()
