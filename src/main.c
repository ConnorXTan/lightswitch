/* main.c — command line for lightswitch.
 *
 * Modes:
 *   run        watch the sensor, fire the bound action for each gesture
 *   monitor    live view of the signal and detector state; never acts
 *   calibrate  characterise the sensor and suggest thresholds
 *   replay     push a recorded trace through the detector
 *
 * Every mode drives the same detector over the same sensor interface, so a
 * bug reproduced under --replay is the same bug seen on hardware.
 */
#include "action.h"
#include "config.h"
#include "detector.h"
#include "sensor.h"
#include "trace.h"
#include "ui.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <signal.h>
#include <unistd.h>
#include <math.h>

#define LS_VERSION "0.2.0"

typedef enum { MODE_RUN, MODE_MONITOR, MODE_CALIBRATE, MODE_REPLAY } ls_mode;

static volatile sig_atomic_t g_stop = 0;

static void on_signal(int sig)
{
    (void)sig;
    g_stop = 1;
}

static void usage(FILE *out)
{
    fprintf(out,
"lightswitch " LS_VERSION " — gestures from the MacBook ambient light sensor\n"
"\n"
"Cup your hand over the top-centre of the display. The shadow is the input:\n"
"a quick cover is a tap, two are a double-tap, holding it there is a hold.\n"
"\n"
"USAGE\n"
"  lightswitch [options]\n"
"\n"
"MODES\n"
"  (default)            watch the sensor and run the bound actions\n"
"  --monitor            live signal + state view; never runs actions\n"
"  --calibrate [SECS]   measure the sensor and suggest thresholds\n"
"\n"
"SOURCE AND RECORDING\n"
"  --replay FILE        read a recorded trace instead of the sensor; combines\n"
"                       with any mode (--monitor --replay, --calibrate --replay)\n"
"  --record FILE        write every sample to FILE (\"-\" for stdout, in which\n"
"                       case all other output moves to stderr)\n"
"\n"
"BINDINGS\n"
"  --on-tap SPEC        SPEC is one of:\n"
"  --on-double-tap SPEC     none                 do nothing\n"
"  --on-hold SPEC           key:cmd+w            send a keystroke\n"
"                           exec:CMD             run CMD with /bin/sh\n"
"  --dry-run            recognise and print gestures, but never act\n"
"\n"
"TUNING\n"
"  --set KEY=VALUE      override any config setting (repeatable)\n"
"  --config FILE        config file to read (default ~/.config/lightswitch/config)\n"
"  --no-config          skip the config file entirely\n"
"  --realtime           with --replay, honour the recorded timing\n"
"\n"
"OTHER\n"
"  --list-keys          print key names usable in key: specs\n"
"  --version, --help\n"
"\n"
"SETTINGS\n"
"  on_tap on_double_tap on_hold poll_ms calibration_ms min_baseline_lux\n"
"  cover_ratio uncover_ratio debounce_samples hold_ms double_gap_ms\n"
"  refractory_ms baseline_alpha\n"
"\n"
"NOTES\n"
"  Turn off System Settings > Displays > \"Automatically adjust brightness\",\n"
"  or macOS will dim the screen as you shade the sensor and fight detection.\n"
"  key: actions need Accessibility permission.\n");
}

static void list_keys(void)
{
    const char *name;
    int col = 0;
    for (size_t i = 0; (name = ls_key_name_at(i)) != NULL; i++) {
        printf("%-10s", name);
        if (++col == 7) {
            putchar('\n');
            col = 0;
        }
    }
    if (col)
        putchar('\n');
    printf("\nModifiers: cmd, shift, alt (option), ctrl. Example: key:cmd+shift+q\n");
}

static const ls_action *action_for(const ls_config *c, ls_gesture g)
{
    switch (g) {
    case LS_GESTURE_TAP:        return &c->on_tap;
    case LS_GESTURE_DOUBLE_TAP: return &c->on_double_tap;
    case LS_GESTURE_HOLD:       return &c->on_hold;
    case LS_GESTURE_NONE:       break;
    }
    return NULL;
}

/* Measure the sensor rather than assuming.
 *
 * The subtlety is separating two things that both look like "spread": the
 * sensor's own noise, and the room genuinely getting brighter or darker over
 * the window. Taking the standard deviation of all readings mixes them and
 * badly overstates the noise. Differencing consecutive *distinct* readings
 * cancels any slow trend, so what is left is the short-term noise — which is
 * the quantity the cover threshold actually has to clear. */
static int run_calibrate(ls_sensor *sensor, double seconds, double poll_ms)
{
    int tty = isatty(STDOUT_FILENO);

    printf("Measuring the sensor for %.0fs. Leave it uncovered and hold still.\n\n",
           seconds);

    double sum = 0.0;
    double lo = 1e30, hi = -1e30;
    long   n = 0, changes = 0, dropped = 0;
    double prev = -1.0, t0 = -1.0, t = 0.0, lux = 0.0;
    double first = -1.0, last = 0.0;

    /* Statistics over successive-difference magnitudes. */
    double dsum = 0.0, dsumsq = 0.0;
    long   dn = 0;

    while (!g_stop) {
        int rc = ls_sensor_read(sensor, &t, &lux);
        if (rc <= 0)
            break;
        if (t0 < 0.0)
            t0 = t;
        if (t - t0 >= seconds * 1000.0)
            break;
        if (lux < 0.0) {
            dropped++;
            continue;
        }
        if (prev >= 0.0 && fabs(lux - prev) > 1e-9) {
            changes++;
            double d = lux - prev;
            dsum += d;
            dsumsq += d * d;
            dn++;
        }
        if (first < 0.0)
            first = lux;
        last = lux;
        prev = lux;
        sum += lux;
        if (lux < lo) lo = lux;
        if (lux > hi) hi = lux;
        n++;

        if (tty && n % 10 == 0) {
            printf("\r  %ld samples, mean %.0f lux ", n, sum / (double)n);
            fflush(stdout);
        }
    }
    if (tty)
        printf("\r%-44s\r", "");

    if (n < 10) {
        fprintf(stderr, "lightswitch: not enough samples to calibrate\n");
        return 1;
    }

    double mean    = sum / (double)n;
    double span    = (t - t0) / 1000.0;
    double refresh = span > 0.0 ? (double)changes / span : 0.0;

    /* Var of a difference of two independent samples is twice the sample
     * variance, hence the sqrt(2). */
    double noise = 0.0;
    if (dn > 1) {
        double dmean = dsum / (double)dn;
        double dvar  = dsumsq / (double)dn - dmean * dmean;
        if (dvar > 0.0)
            noise = sqrt(dvar) / sqrt(2.0);
    }

    double drift    = last - first;
    double worst_dip = mean > 0.0 ? (mean - lo) / mean * 100.0 : 0.0;

    printf("samples          %ld over %.1fs (polled every %.0f ms)\n", n, span, poll_ms);
    printf("dropped reads    %ld\n", dropped);
    printf("mean             %.1f lux\n", mean);
    printf("range            %.1f .. %.1f lux\n", lo, hi);
    printf("refresh rate     ~%.1f Hz (value changed %ld times)\n", refresh, changes);
    printf("short-term noise %.2f lux (%.3f%% of mean, 1 sigma between updates)\n",
           noise, mean > 0.0 ? noise / mean * 100.0 : 0.0);
    printf("ambient drift    %+.0f lux over the window (%.1f%% of mean)\n",
           drift, mean > 0.0 ? fabs(drift) / mean * 100.0 : 0.0);

    if (refresh > 0.0 && poll_ms < 1000.0 / refresh * 0.8) {
        printf("\nNote: polling is faster than the sensor refreshes, so consecutive\n"
               "      reads repeat the same latched value. debounce_samples must\n"
               "      span more than %.0f ms to see two independent readings.\n",
               1000.0 / refresh);
    }
    if (mean < 25.0) {
        printf("\nThis room is too dark for reliable detection (need ~25 lux or more).\n");
        return 1;
    }

    /* The threshold has to clear the worst downward excursion seen while the
     * sensor was uncovered, whatever its cause. */
    double margin_pct = 100.0 * (1.0 - 0.45);
    printf("\nThresholds\n");
    printf("  cover_ratio 0.45 triggers %.0f%% below baseline;\n", margin_pct);
    printf("  the deepest dip observed while uncovered was %.1f%% below the mean", worst_dip);
    if (worst_dip > 1e-9)
        printf(" (%.0fx margin).\n", margin_pct / worst_dip);
    else
        printf(".\n");

    if (worst_dip > margin_pct * 0.5) {
        printf("\n  This room is unstable enough that the default could false-trigger.\n"
               "  Try a lower cover_ratio (a deeper shadow required), e.g.\n"
               "      lightswitch --set cover_ratio=%.2f\n",
               (100.0 - worst_dip * 2.0) / 100.0 < 0.1
                   ? 0.10 : (100.0 - worst_dip * 2.0) / 100.0);
    }
    return 0;
}

int main(int argc, char **argv)
{
    ls_config cfg;
    ls_config_defaults(&cfg);

    ls_mode mode = MODE_RUN;
    const char *config_path = NULL;
    const char *replay_path = NULL;
    const char *record_path = NULL;
    int no_config = 0, dry_run = 0, realtime = 0;
    double calibrate_secs = 10.0;
    char err[256];

    /* Pass one: only the flags that decide which config file to read, so the
     * file can be loaded before the remaining flags override it. */
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
            usage(stdout);
            return 0;
        }
        if (!strcmp(argv[i], "--version")) {
            printf("lightswitch %s\n", LS_VERSION);
            return 0;
        }
        if (!strcmp(argv[i], "--list-keys")) {
            list_keys();
            return 0;
        }
        if (!strcmp(argv[i], "--no-config")) {
            no_config = 1;
        } else if (!strcmp(argv[i], "--config")) {
            if (++i >= argc) {
                fprintf(stderr, "lightswitch: --config needs a path\n");
                return 2;
            }
            config_path = argv[i];
        }
    }

    if (!no_config) {
        char path[1024];
        if (config_path) {
            snprintf(path, sizeof(path), "%s", config_path);
        } else if (ls_config_default_path(path, sizeof(path)) != 0) {
            path[0] = '\0';
        }
        if (path[0]) {
            int rc = ls_config_load_file(&cfg, path, err, sizeof(err));
            if (rc < 0) {
                fprintf(stderr, "lightswitch: %s\n", err);
                return 2;
            }
            if (rc == 0 && config_path) {
                fprintf(stderr, "lightswitch: config file not found: %s\n", path);
                return 2;
            }
        }
    }

    /* Pass two: everything else, applied on top of the config file. */
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];

        if (!strcmp(a, "--no-config")) {
            continue;
        } else if (!strcmp(a, "--config")) {
            i++;
            continue;
        } else if (!strcmp(a, "--monitor")) {
            mode = MODE_MONITOR;
        } else if (!strcmp(a, "--dry-run")) {
            dry_run = 1;
        } else if (!strcmp(a, "--realtime")) {
            realtime = 1;
        } else if (!strcmp(a, "--calibrate")) {
            mode = MODE_CALIBRATE;
            if (i + 1 < argc && argv[i + 1][0] != '-') {
                calibrate_secs = strtod(argv[++i], NULL);
                if (calibrate_secs <= 0.0)
                    calibrate_secs = 10.0;
            }
        } else if (!strcmp(a, "--replay")) {
            if (++i >= argc) {
                fprintf(stderr, "lightswitch: --replay needs a file\n");
                return 2;
            }
            /* --replay chooses the *source*, not the mode, so it composes:
             * --monitor --replay and --calibrate --replay both work. */
            replay_path = argv[i];
        } else if (!strcmp(a, "--record")) {
            if (++i >= argc) {
                fprintf(stderr, "lightswitch: --record needs a file\n");
                return 2;
            }
            record_path = argv[i];
        } else if (!strcmp(a, "--set")) {
            if (++i >= argc) {
                fprintf(stderr, "lightswitch: --set needs key=value\n");
                return 2;
            }
            if (ls_config_set_assignment(&cfg, argv[i], err, sizeof(err)) != 0) {
                fprintf(stderr, "lightswitch: %s\n", err);
                return 2;
            }
        } else if (!strcmp(a, "--on-tap") || !strcmp(a, "--on-double-tap") ||
                   !strcmp(a, "--on-hold")) {
            const char *key = !strcmp(a, "--on-tap")  ? "on_tap"
                            : !strcmp(a, "--on-hold") ? "on_hold"
                                                      : "on_double_tap";
            if (++i >= argc) {
                fprintf(stderr, "lightswitch: %s needs an action\n", a);
                return 2;
            }
            if (ls_config_set(&cfg, key, argv[i], err, sizeof(err)) != 0) {
                fprintf(stderr, "lightswitch: %s\n", err);
                return 2;
            }
        } else {
            fprintf(stderr, "lightswitch: unknown option \"%s\" (try --help)\n", a);
            return 2;
        }
    }

    if (replay_path && mode == MODE_RUN)
        mode = MODE_REPLAY;
    if (mode == MODE_REPLAY && !replay_path) {
        fprintf(stderr, "lightswitch: --replay needs a file\n");
        return 2;
    }

    if (ls_detector_config_validate(&cfg.detector, err, sizeof(err)) != 0) {
        fprintf(stderr, "lightswitch: %s\n", err);
        return 2;
    }
    if (cfg.poll_ms < 1.0 || cfg.poll_ms > 5000.0) {
        fprintf(stderr, "lightswitch: poll_ms must be between 1 and 5000\n");
        return 2;
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGCHLD, SIG_IGN); /* exec: actions are fire-and-forget */

    /* A trace substitutes for the sensor in every mode, not just --replay, so
     * calibration figures can be recomputed from a recording. */
    ls_sensor *sensor = NULL;
    if (replay_path) {
        sensor = ls_sensor_open_replay(replay_path, realtime, err, sizeof(err));
    } else {
#if LS_HAVE_IOKIT
        sensor = ls_sensor_open_iokit(cfg.poll_ms, err, sizeof(err));
#else
        snprintf(err, sizeof(err),
                 "this build has no live sensor backend; use --replay FILE");
#endif
    }
    if (!sensor) {
        fprintf(stderr, "lightswitch: %s\n", err);
        return 1;
    }

    if (mode == MODE_CALIBRATE) {
        int rc = run_calibrate(sensor, calibrate_secs, cfg.poll_ms);
        ls_sensor_close(sensor);
        return rc;
    }

    ls_trace_writer *rec = NULL;
    if (record_path) {
        rec = ls_trace_open_write(record_path, "recorded by lightswitch",
                                  err, sizeof(err));
        if (!rec) {
            fprintf(stderr, "lightswitch: %s\n", err);
            ls_sensor_close(sensor);
            return 1;
        }
    }

    int act = !dry_run && mode == MODE_RUN && ls_config_has_bindings(&cfg);

    ls_detector det;
    ls_detector_init(&det, &cfg.detector);

    /* When the trace is going to stdout, nothing else may: gesture lines and
     * the monitor move to stderr so the recording stays parseable. */
    int   quiet = (record_path && !strcmp(record_path, "-"));
    FILE *out   = quiet ? stderr : stdout;

    if (!quiet) {
        fprintf(stderr, "lightswitch %s | source: %s | %s\n",
                LS_VERSION, ls_sensor_kind(sensor),
                act ? "actions ARMED" : "dry run (no actions)");
        fprintf(stderr, "  tap        -> %s\n", ls_action_describe(&cfg.on_tap));
        fprintf(stderr, "  double-tap -> %s\n", ls_action_describe(&cfg.on_double_tap));
        fprintf(stderr, "  hold       -> %s\n", ls_action_describe(&cfg.on_hold));
        if (mode != MODE_REPLAY)
            fprintf(stderr, "\ncalibrating for %.1fs — do not shade the screen...\n",
                    cfg.detector.calibration_ms / 1000.0);
    }

    /* The live view owns the terminal from here on, which is why it is opened
     * after the banner above rather than with the rest of the setup. */
    ls_ui *ui = NULL;
    if (mode == MODE_MONITOR && !quiet) {
        ui = ls_ui_open(out, ls_sensor_kind(sensor), act);
        if (!ui) {
            fprintf(stderr, "lightswitch: out of memory\n");
            ls_sensor_close(sensor);
            return 1;
        }
        ls_ui_binding(ui, LS_GESTURE_TAP,        ls_action_describe(&cfg.on_tap));
        ls_ui_binding(ui, LS_GESTURE_DOUBLE_TAP, ls_action_describe(&cfg.on_double_tap));
        ls_ui_binding(ui, LS_GESTURE_HOLD,       ls_action_describe(&cfg.on_hold));
    }

    int   calibrated = 0;
    long  gestures = 0;
    int   exit_code = 0;
    double t = 0.0, lux = 0.0;

    while (!g_stop) {
        int rc = ls_sensor_read(sensor, &t, &lux);
        if (rc == 0)
            break;
        if (rc < 0) {
            exit_code = 1;
            break;
        }

        if (rec && ls_trace_write(rec, t, lux) != 0) {
            fprintf(stderr, "lightswitch: failed writing trace\n");
            exit_code = 1;
            break;
        }

        ls_gesture g = ls_detector_push(&det, t, lux);

        if (ls_detector_state(&det) == LS_STATE_FAULT) {
            if (!quiet)
                fprintf(stderr, "\nlightswitch: %s\n", ls_detector_fault(&det));
            exit_code = 1;
            break;
        }
        if (ui)
            ls_ui_sample(ui, t, lux, &det);

        if (!calibrated && ls_detector_state(&det) != LS_STATE_CALIBRATING) {
            calibrated = 1;
            if (!quiet && !ls_ui_is_visual(ui)) {
                double base = ls_detector_baseline(&det);
                fprintf(stderr,
                        "baseline %.0f lux | cover below %.0f | release above %.0f\n",
                        base, base * cfg.detector.cover_ratio,
                        base * cfg.detector.uncover_ratio);
                fprintf(stderr, "\nReady. Cup your hand over the top of the screen.\n\n");
            }
        }

        if (ui)
            ls_ui_render(ui);

        if (g != LS_GESTURE_NONE) {
            gestures++;

            const ls_action *action = action_for(&cfg, g);
            int bound = action && action->kind != LS_ACTION_NONE;

            /* Build the line once. Whether it belongs on a plain stream or in
             * the live view is the sink's problem, not this loop's. */
            char line[192];
            int  p = snprintf(line, sizeof line, "[%7.1fs] %s",
                              t / 1000.0, ls_gesture_name(g));
            if (p < 0 || p >= (int)sizeof line) p = (int)sizeof line - 1;

            if (bound) {
                /* Pad the gesture name only when something follows it, so an
                 * unbound gesture leaves no trailing spaces in a log. */
                int pad = (int)(11 - strlen(ls_gesture_name(g)));
                int n = snprintf(line + p, sizeof line - p, "%*s", pad, "");
                if (n > 0) p += n;
                if (p >= (int)sizeof line) p = (int)sizeof line - 1;

                if (act) {
                    if (ls_action_run(action, err, sizeof(err)) != 0)
                        /* %.128s: err can be 255 bytes, more than fits in line;
                         * cap it so gcc can prove the truncation is deliberate. */
                        snprintf(line + p, sizeof line - p, " -> FAILED: %.128s", err);
                    else
                        snprintf(line + p, sizeof line - p, " -> %s",
                                 ls_action_describe(action));
                } else {
                    snprintf(line + p, sizeof line - p, " -> would run %s",
                             ls_action_describe(action));
                }
            }

            if (ui) {
                ls_ui_count(ui, g);
                ls_ui_gesture(ui, t, line);   /* prints plainly when not a tty */
                ls_ui_render(ui);
            } else {
                fprintf(out, "%s\n", line);
                fflush(out);
            }
        }
    }

    ls_ui_close(ui);

    if (rec && ls_trace_close_write(rec) != 0) {
        fprintf(stderr, "lightswitch: failed closing trace\n");
        exit_code = 1;
    }
    ls_sensor_close(sensor);

    if (mode == MODE_REPLAY && !quiet)
        fprintf(stderr, "replay finished: %ld gesture%s\n",
                gestures, gestures == 1 ? "" : "s");
    return exit_code;
}
