/* lstrace-synth — generate light sensor traces for tests and demos.
 *
 * The fixtures in tests/traces are produced by this tool so they are
 * reproducible and reviewable, and so anyone without a MacBook can still
 * exercise the whole pipeline. The model reproduces the three properties of
 * the real sensor that actually matter to the detector (see docs/SIGNAL.md):
 *
 *   1. sample-and-hold — the sensor refreshes near 4.7 Hz while we poll at
 *      10 Hz, so consecutive samples repeat;
 *   2. a small proportional noise floor, ~0.12% of the reading;
 *   3. finite edges — a hand takes a few tens of milliseconds to arrive.
 *
 * usage: lstrace-synth <scenario>   (writes a trace to stdout)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define POLL_MS      100.0
#define REFRESH_MS   211.0   /* measured sensor update period */
#define NOISE_FRAC   0.0012
#define EDGE_MS      70.0    /* how long a hand takes to cover the sensor */

typedef struct {
    double start_ms;
    double end_ms;
    double depth;   /* fraction of light remaining while covered */
} span;

typedef struct {
    const char *name;
    const char *note;
    double      duration_ms;
    double      baseline_start;
    double      baseline_end;
    span        spans[8];
    int         nspans;
} scenario;

static const scenario SCENARIOS[] = {
    { "idle", "quiet room, nothing happening", 30000, 4830, 4830,
      {{0}}, 0 },

    /* Cover durations here are what a deliberate gesture actually looks like.
     * Anything much under ~400 ms is shorter than two sensor refreshes and is
     * not reliably detectable — see docs/SIGNAL.md. */
    { "tap", "one quick cover of the sensor", 10000, 4830, 4830,
      {{5000, 5500, 0.02}}, 1 },

    { "double_tap", "two covers inside the double-tap window", 10000, 4830, 4830,
      {{5000, 5450, 0.02}, {5800, 6250, 0.02}}, 2 },

    { "hold", "hand held over the sensor for 1.8s", 10000, 4830, 4830,
      {{5000, 6800, 0.02}}, 1 },

    { "walk_past", "someone crossing the room: partial, slow shadows", 20000, 4830, 4830,
      {{4000, 5200, 0.72}, {9000, 11000, 0.83}, {15000, 15600, 0.66}}, 3 },

    { "drift", "daylight fading from 4830 to 2400 lux over five minutes",
      300000, 4830, 2400, {{0}}, 0 },

    { "dark", "a room too dim to work in", 10000, 12, 12,
      {{5000, 5500, 0.02}}, 1 },

    { "office_session", "a realistic minute: two taps, a hold, and a passer-by",
      60000, 4830, 4600,
      {{6000, 6500, 0.02},                    /* tap              */
       {14000, 15400, 0.78},                  /* someone walks by */
       {24000, 24450, 0.02}, {24800, 25250, 0.02}, /* double tap   */
       {40000, 42000, 0.02}},                 /* hold             */
      5 },
};

static const size_t NSCENARIOS = sizeof(SCENARIOS) / sizeof(SCENARIOS[0]);

static unsigned rng_state = 987654321u;

static double noise_unit(void)
{
    rng_state = rng_state * 1103515245u + 12345u;
    double u = (double)((rng_state >> 16) & 0x7fff) / 32767.0;
    return u * 2.0 - 1.0;
}

/* Smooth 0..1 ramp; a hand does not teleport onto the sensor. */
static double smoothstep(double x)
{
    if (x <= 0.0) return 0.0;
    if (x >= 1.0) return 1.0;
    return x * x * (3.0 - 2.0 * x);
}

static double occlusion(const scenario *s, double t)
{
    double factor = 1.0;
    for (int i = 0; i < s->nspans; i++) {
        const span *sp = &s->spans[i];
        double in  = smoothstep((t - sp->start_ms) / EDGE_MS);
        double out = smoothstep((sp->end_ms - t) / EDGE_MS);
        double amount = in < out ? in : out;
        if (amount <= 0.0)
            continue;
        double f = 1.0 + (sp->depth - 1.0) * amount;
        if (f < factor)
            factor = f;
    }
    return factor;
}

/* What the sensor hardware would latch if it refreshed at time t. */
static double sample_at(const scenario *s, double t)
{
    double frac     = s->duration_ms > 0.0 ? t / s->duration_ms : 0.0;
    double baseline = s->baseline_start +
                      (s->baseline_end - s->baseline_start) * frac;
    double v = baseline * occlusion(s, t) + noise_unit() * baseline * NOISE_FRAC;
    return v < 0.0 ? 0.0 : v;
}

static void emit(const scenario *s)
{
    printf("# lightswitch trace v1\n");
    printf("# note: %s\n", s->note);
    printf("# synthesised by lstrace-synth (%s); regenerate with `make traces`\n",
           s->name);

    /* The sensor free-runs on its own REFRESH_MS grid; we poll on a different
     * one and read whatever is currently latched. Advancing last_refresh by
     * exactly REFRESH_MS (rather than snapping it to the poll time) is what
     * keeps the two grids independent — snapping quantises the sensor onto
     * the poll grid and can make short gestures vanish between samples. */
    double last_refresh = 0.0;
    double held = sample_at(s, 0.0);

    for (double t = 0.0; t <= s->duration_ms; t += POLL_MS) {
        while (t - last_refresh >= REFRESH_MS) {
            last_refresh += REFRESH_MS;
            held = sample_at(s, last_refresh);
        }
        printf("%.1f %.2f\n", t, held);
    }
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: lstrace-synth <scenario>\n\nscenarios:\n");
        for (size_t i = 0; i < NSCENARIOS; i++)
            fprintf(stderr, "  %-16s %s\n", SCENARIOS[i].name, SCENARIOS[i].note);
        return 2;
    }
    for (size_t i = 0; i < NSCENARIOS; i++) {
        if (strcmp(argv[1], SCENARIOS[i].name) == 0) {
            emit(&SCENARIOS[i]);
            return 0;
        }
    }
    fprintf(stderr, "lstrace-synth: unknown scenario \"%s\"\n", argv[1]);
    return 2;
}
