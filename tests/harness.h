/* harness.h — a deliberately tiny test harness.
 *
 * A C project that pulls in a unit-test framework to check a few hundred
 * lines of logic has usually made itself harder to build, not easier to
 * trust. Everything needed here is a counter and two macros.
 */
#ifndef LS_TEST_HARNESS_H
#define LS_TEST_HARNESS_H

#include <stdio.h>
#include <math.h>

static int ls_checks_run;
static int ls_checks_failed;
static const char *ls_current_test;

#define CHECK(cond)                                                          \
    do {                                                                     \
        ls_checks_run++;                                                     \
        if (!(cond)) {                                                       \
            ls_checks_failed++;                                              \
            fprintf(stderr, "    FAIL %s:%d in %s: %s\n",                    \
                    __FILE__, __LINE__, ls_current_test, #cond);             \
        }                                                                    \
    } while (0)

#define CHECK_EQ(actual, expected)                                           \
    do {                                                                     \
        ls_checks_run++;                                                     \
        long _a = (long)(actual), _e = (long)(expected);                     \
        if (_a != _e) {                                                      \
            ls_checks_failed++;                                              \
            fprintf(stderr, "    FAIL %s:%d in %s: %s == %s (got %ld,"       \
                            " want %ld)\n",                                  \
                    __FILE__, __LINE__, ls_current_test, #actual, #expected, \
                    _a, _e);                                                 \
        }                                                                    \
    } while (0)

#define CHECK_NEAR(actual, expected, tol)                                    \
    do {                                                                     \
        ls_checks_run++;                                                     \
        double _a = (double)(actual), _e = (double)(expected);               \
        if (!(fabs(_a - _e) <= (tol))) {                                     \
            ls_checks_failed++;                                              \
            fprintf(stderr, "    FAIL %s:%d in %s: %s ~= %s (got %g,"        \
                            " want %g +/- %g)\n",                            \
                    __FILE__, __LINE__, ls_current_test, #actual, #expected, \
                    _a, _e, (double)(tol));                                  \
        }                                                                    \
    } while (0)

#define CHECK_STR(actual, expected)                                          \
    do {                                                                     \
        ls_checks_run++;                                                     \
        if (strcmp((actual), (expected)) != 0) {                             \
            ls_checks_failed++;                                              \
            fprintf(stderr, "    FAIL %s:%d in %s: got \"%s\", want \"%s\"\n",\
                    __FILE__, __LINE__, ls_current_test,                     \
                    (actual), (expected));                                   \
        }                                                                    \
    } while (0)

#define RUN(fn)                                                              \
    do {                                                                     \
        ls_current_test = #fn;                                               \
        int _before = ls_checks_failed;                                      \
        fn();                                                                \
        fprintf(stderr, "  %s %s\n",                                         \
                ls_checks_failed == _before ? "ok  " : "FAIL", #fn);         \
    } while (0)

#define TEST_MAIN_BEGIN(suite)                                               \
    int main(void)                                                           \
    {                                                                        \
        fprintf(stderr, "%s\n", suite);

#define TEST_MAIN_END()                                                      \
        fprintf(stderr, "%d checks, %d failed\n\n",                          \
                ls_checks_run, ls_checks_failed);                            \
        return ls_checks_failed == 0 ? 0 : 1;                                \
    }

#endif /* LS_TEST_HARNESS_H */
