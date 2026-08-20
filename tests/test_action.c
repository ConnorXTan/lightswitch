/* test_action.c — action spec parsing.
 *
 * Only running a key action needs macOS; deciding what "cmd+shift+q" means is
 * pure string work and is checked everywhere. */
#include "action.h"
#include "harness.h"

#include <string.h>

static void test_none(void)
{
    ls_action a;
    char err[128];

    CHECK_EQ(ls_action_parse("none", &a, err, sizeof(err)), 0);
    CHECK_EQ(a.kind, LS_ACTION_NONE);

    CHECK_EQ(ls_action_parse("", &a, err, sizeof(err)), 0);
    CHECK_EQ(a.kind, LS_ACTION_NONE);
}

static void test_simple_key(void)
{
    ls_action a;
    char err[128];

    CHECK_EQ(ls_action_parse("key:w", &a, err, sizeof(err)), 0);
    CHECK_EQ(a.kind, LS_ACTION_KEY);
    CHECK_EQ(a.keycode, 13);
    CHECK_EQ(a.modifiers, 0);
}

static void test_modifiers(void)
{
    ls_action a;
    char err[128];

    CHECK_EQ(ls_action_parse("key:cmd+w", &a, err, sizeof(err)), 0);
    CHECK_EQ(a.keycode, 13);
    CHECK_EQ(a.modifiers, LS_MOD_CMD);

    CHECK_EQ(ls_action_parse("key:cmd+shift+q", &a, err, sizeof(err)), 0);
    CHECK_EQ(a.keycode, 12);
    CHECK_EQ(a.modifiers, LS_MOD_CMD | LS_MOD_SHIFT);

    /* Aliases and spacing that people actually type. */
    CHECK_EQ(ls_action_parse("key:COMMAND + W", &a, err, sizeof(err)), 0);
    CHECK_EQ(a.keycode, 13);
    CHECK_EQ(a.modifiers, LS_MOD_CMD);

    CHECK_EQ(ls_action_parse("key:option+ctrl+escape", &a, err, sizeof(err)), 0);
    CHECK_EQ(a.keycode, 53);
    CHECK_EQ(a.modifiers, LS_MOD_ALT | LS_MOD_CTRL);
}

static void test_named_keys(void)
{
    CHECK_EQ(ls_keycode_for_name("space"), 49);
    CHECK_EQ(ls_keycode_for_name("return"), 36);
    CHECK_EQ(ls_keycode_for_name("f5"), 96);
    CHECK_EQ(ls_keycode_for_name("up"), 126);
    CHECK_EQ(ls_keycode_for_name("W"), 13); /* case-insensitive */
    CHECK_EQ(ls_keycode_for_name("nope"), -1);
}

static void test_bad_keys(void)
{
    ls_action a;
    char err[128];

    CHECK_EQ(ls_action_parse("key:cmd", &a, err, sizeof(err)), -1);
    CHECK(strstr(err, "no key") != NULL);

    CHECK_EQ(ls_action_parse("key:w+q", &a, err, sizeof(err)), -1);
    CHECK_EQ(ls_action_parse("key:frobnicate", &a, err, sizeof(err)), -1);
    CHECK(strstr(err, "--list-keys") != NULL);

    CHECK_EQ(ls_action_parse("key:cmd+", &a, err, sizeof(err)), -1);
}

static void test_exec(void)
{
    ls_action a;
    char err[128];

    CHECK_EQ(ls_action_parse("exec:open -a Finder", &a, err, sizeof(err)), 0);
    CHECK_EQ(a.kind, LS_ACTION_EXEC);
    CHECK_STR(a.command, "open -a Finder");

    CHECK_EQ(ls_action_parse("exec:   ", &a, err, sizeof(err)), -1);
}

static void test_unknown_scheme(void)
{
    ls_action a;
    char err[128];
    CHECK_EQ(ls_action_parse("launch:thing", &a, err, sizeof(err)), -1);
    CHECK(strstr(err, "unknown action") != NULL);
}

static void test_describe_round_trips(void)
{
    ls_action a;
    char err[128];
    CHECK_EQ(ls_action_parse("key:cmd+w", &a, err, sizeof(err)), 0);
    CHECK_STR(ls_action_describe(&a), "key:cmd+w");
}

static void test_key_name_enumeration_terminates(void)
{
    size_t n = 0;
    while (ls_key_name_at(n) != NULL) {
        n++;
        if (n > 10000)
            break;
    }
    CHECK(n > 40);
    CHECK(n < 10000);
}

TEST_MAIN_BEGIN("action")
    RUN(test_none);
    RUN(test_simple_key);
    RUN(test_modifiers);
    RUN(test_named_keys);
    RUN(test_bad_keys);
    RUN(test_exec);
    RUN(test_unknown_scheme);
    RUN(test_describe_round_trips);
    RUN(test_key_name_enumeration_terminates);
TEST_MAIN_END()
