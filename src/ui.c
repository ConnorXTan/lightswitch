/* ui.c — the live view. See ui.h for why this module exists.
 *
 * Two rules keep this from becoming a liability:
 *
 *   1. It never touches the detector. It reads a snapshot and draws it, so a
 *      rendering bug can change what you see but not what is recognised.
 *   2. It degrades. If stdout is not a terminal the whole escape-sequence
 *      layer switches off and gestures print as plain lines, because the
 *      alternative is a log file full of cursor-movement bytes.
 */
#include "ui.h"

#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>

/* ---- diagnosis ---------------------------------------------------------- */

/* Thresholds here are in milliseconds of *persistence*. They are all well
 * above one sensor refresh (~211 ms bright, ~2.5 s dim) so that a single slow
 * update never trips a warning. */
#define DEAD_ZONE_MS   2500.0
#define LATCHED_MS     3000.0
#define SPENT_MS       6000.0
#define DIM_BASELINE   150.0

ls_diag_level ls_diag(const ls_diag_input *in, char *msg, size_t len)
{
    if (!in || !msg || len == 0)
        return LS_DIAG_OK;
    msg[0] = '\0';

    if (in->state == LS_STATE_CALIBRATING)
        return LS_DIAG_OK;

    /* The wedge. The signal is too dark to count as uncovered and too bright
     * to count as covered, so no edge can ever complete: the detector is
     * stuck until something moves it. This is the failure that looks like
     * "the app stopped working" and it is worth naming precisely. */
    int dead = in->ratio > in->cover_ratio && in->ratio < in->uncover_ratio;
    if (dead && in->below_release_ms >= DEAD_ZONE_MS) {
        snprintf(msg, len,
                 "stalled between the thresholds for %.0fs: %.0f%% of baseline is "
                 "below release (%.0f%%) but above cover (%.0f%%), so nothing "
                 "can complete. Usually auto-brightness dimming the screen.",
                 in->below_release_ms / 1000.0, in->ratio * 100.0,
                 in->uncover_ratio * 100.0, in->cover_ratio * 100.0);
        return LS_DIAG_WARN;
    }

    /* Polling faster than the sensor updates is normal; polling faster than a
     * whole gesture is not. Below roughly 25 lux of ambient the VD6286 slows
     * down enough that a deliberate tap can land entirely inside one latched
     * reading and be invisible. */
    if (in->latched_ms >= LATCHED_MS) {
        snprintf(msg, len,
                 "sensor has repeated the same reading for %.1fs — it updates "
                 "this slowly in dim light, and a gesture shorter than that "
                 "cannot be seen at all.",
                 in->latched_ms / 1000.0);
        return LS_DIAG_WARN;
    }

    if (in->state == LS_STATE_SPENT && in->below_release_ms >= SPENT_MS) {
        snprintf(msg, len,
                 "gesture fired %.0fs ago and the sensor has not come back "
                 "above release (%.0f%%) since. Uncover it to re-arm.",
                 in->below_release_ms / 1000.0, in->uncover_ratio * 100.0);
        return LS_DIAG_NOTE;
    }

    if (in->baseline > 0.0 && in->baseline < DIM_BASELINE) {
        snprintf(msg, len,
                 "baseline is only %.0f lux. Cover must reach %.0f and release "
                 "must clear %.0f — a %.0f lux window. It works, but a brighter "
                 "room gives far more margin.",
                 in->baseline, in->baseline * in->cover_ratio,
                 in->baseline * in->uncover_ratio,
                 in->baseline * (in->uncover_ratio - in->cover_ratio));
        return LS_DIAG_NOTE;
    }

    return LS_DIAG_OK;
}

/* ---- terminal plumbing -------------------------------------------------- */

#define MAX_COLS   200
#define MAX_ROWS   14
#define LOG_LINES  6
#define GUTTER     7      /* five columns of label, a space, the axis rule */
#define SB_CAP     65536

typedef struct {
    double t, lux;
    unsigned char state;
} sample;

struct ls_ui {
    FILE *out;
    int   visual;
    int   utf8;
    int   armed;
    char  source[24];
    char  bind[3][64];

    sample ring[MAX_COLS];
    int    head, count;

    char   log[LOG_LINES][120];
    int    logn;
    long   counts[4];

    /* Latest snapshot of the detector, copied not referenced. */
    int      have;
    double   t_now, lux, baseline, ratio;
    ls_state state;
    ls_detector_config cfg;

    double t_start;
    double t_cover_start;    /* copied from the detector, for the countdown */
    double t_release;
    double t_above_release;  /* last time the signal was clearly uncovered  */
    double t_lux_changed;
    double prev_lux;

    char   sb[SB_CAP];
    size_t sblen;
};

static void sb_reset(ls_ui *ui) { ui->sblen = 0; ui->sb[0] = '\0'; }

static void sb_add(ls_ui *ui, const char *s)
{
    size_t n = strlen(s);
    if (ui->sblen + n + 1 >= SB_CAP) return;
    memcpy(ui->sb + ui->sblen, s, n);
    ui->sblen += n;
    ui->sb[ui->sblen] = '\0';
}

static void sb_addf(ls_ui *ui, const char *fmt, ...)
{
    char tmp[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap);
    sb_add(ui, tmp);
}

/* End the line: erase whatever the previous frame left to the right. Redrawing
 * in place rather than clearing the screen is what keeps the view from
 * flickering at a 10 Hz refresh. */
static void sb_eol(ls_ui *ui) { sb_add(ui, "\033[K\n"); }

static int term_size(FILE *out, int *cols, int *rows)
{
    *cols = 80; *rows = 24;
#ifdef TIOCGWINSZ
    struct winsize ws;
    if (ioctl(fileno(out), TIOCGWINSZ, &ws) == 0) {
        if (ws.ws_col > 0) *cols = ws.ws_col;
        if (ws.ws_row > 0) *rows = ws.ws_row;
        return 0;
    }
#else
    (void)out;
#endif
    return -1;
}

static int env_is_utf8(void)
{
    const char *v = getenv("LC_ALL");
    if (!v || !*v) v = getenv("LC_CTYPE");
    if (!v || !*v) v = getenv("LANG");
    if (!v) return 0;
    return strstr(v, "UTF-8") != NULL || strstr(v, "utf8") != NULL ||
           strstr(v, "UTF8")  != NULL || strstr(v, "utf-8") != NULL;
}

/* ---- glyphs ------------------------------------------------------------- */

static const char *BLOCK_U[8] = {"▁","▂","▃","▄",
                                 "▅","▆","▇","█"};
static const char *BLOCK_A[8] = {".",".",":",":","o","o","O","#"};

static const char *glyph(const ls_ui *ui, int level)
{
    if (level < 0) level = 0;
    if (level > 7) level = 7;
    return ui->utf8 ? BLOCK_U[level] : BLOCK_A[level];
}

/* ANSI colour by detector state, so the trace itself shows what the state
 * machine believed at the moment each sample arrived. */
static const char *state_colour(ls_state s)
{
    switch (s) {
    case LS_STATE_CALIBRATING: return "\033[90m";
    case LS_STATE_IDLE:        return "\033[32m";
    case LS_STATE_COVERED:     return "\033[91m";
    case LS_STATE_TAP_PENDING: return "\033[96m";
    case LS_STATE_SPENT:       return "\033[95m";
    case LS_STATE_FAULT:       return "\033[31m";
    }
    return "\033[0m";
}

/* ---- lifecycle ---------------------------------------------------------- */

ls_ui *ls_ui_open(FILE *out, const char *source, int armed)
{
    ls_ui *ui = calloc(1, sizeof(*ui));
    if (!ui) return NULL;

    ui->out    = out;
    ui->visual = isatty(fileno(out));
    ui->utf8   = env_is_utf8();
    ui->armed  = armed;
    snprintf(ui->source, sizeof(ui->source), "%s", source ? source : "?");
    for (int i = 0; i < 3; i++)
        snprintf(ui->bind[i], sizeof(ui->bind[i]), "none");
    ui->prev_lux = -1.0;

    if (ui->visual) {
        /* Alternate screen: the live view is transient, and clobbering the
         * user's scrollback with 400 frames of it would be rude. */
        fputs("\033[?1049h\033[?25l", out);
        fflush(out);
    }
    return ui;
}

void ls_ui_close(ls_ui *ui)
{
    if (!ui) return;
    if (ui->visual) {
        /* Leaving the alternate screen discards the view, so the numbers the
         * session produced are reprinted onto the real scrollback. */
        fputs("\033[?25h\033[?1049l", ui->out);
        fprintf(ui->out,
                "lightswitch: %.0fs, %ld gesture%s"
                " (tap %ld, double-tap %ld, hold %ld)\n",
                (ui->t_now - ui->t_start) / 1000.0, (long)ui->logn,
                ui->logn == 1 ? "" : "s",
                ui->counts[LS_GESTURE_TAP], ui->counts[LS_GESTURE_DOUBLE_TAP],
                ui->counts[LS_GESTURE_HOLD]);
        fflush(ui->out);
    }
    free(ui);
}

int ls_ui_is_visual(const ls_ui *ui) { return ui ? ui->visual : 0; }

void ls_ui_binding(ls_ui *ui, ls_gesture g, const char *desc)
{
    if (!ui || g < LS_GESTURE_TAP || g > LS_GESTURE_HOLD) return;
    snprintf(ui->bind[g - 1], sizeof(ui->bind[0]), "%s", desc ? desc : "none");
}

void ls_ui_sample(ls_ui *ui, double t_ms, double lux, const ls_detector *d)
{
    if (!ui || !d) return;

    if (!ui->have) {
        ui->t_start         = t_ms;
        ui->t_above_release = t_ms;
        ui->t_lux_changed   = t_ms;
        ui->have            = 1;
    }

    ui->t_now    = t_ms;
    ui->lux      = lux;
    ui->baseline = ls_detector_baseline(d);
    ui->ratio    = ls_detector_ratio(d);
    ui->state    = ls_detector_state(d);
    ui->cfg      = d->cfg;

    /* Read-only peek at the detector's own clocks so the view can show what
     * it is waiting for. Copied, never written back. */
    ui->t_cover_start = d->t_cover_start;
    ui->t_release     = d->t_release;

    if (ui->ratio >= d->cfg.uncover_ratio || ui->state == LS_STATE_CALIBRATING)
        ui->t_above_release = t_ms;
    if (lux != ui->prev_lux) {
        ui->t_lux_changed = t_ms;
        ui->prev_lux      = lux;
    }

    ui->ring[ui->head].t     = t_ms;
    ui->ring[ui->head].lux   = lux;
    ui->ring[ui->head].state = (unsigned char)ui->state;
    ui->head = (ui->head + 1) % MAX_COLS;
    if (ui->count < MAX_COLS) ui->count++;
}

void ls_ui_gesture(ls_ui *ui, double t_ms, const char *text)
{
    if (!ui || !text) return;
    (void)t_ms;

    if (ui->logn < LOG_LINES) {
        snprintf(ui->log[ui->logn], sizeof(ui->log[0]), "%s", text);
    } else {
        for (int i = 0; i < LOG_LINES - 1; i++)
            memcpy(ui->log[i], ui->log[i + 1], sizeof(ui->log[0]));
        snprintf(ui->log[LOG_LINES - 1], sizeof(ui->log[0]), "%s", text);
    }
    ui->logn++;

    if (!ui->visual) {
        fprintf(ui->out, "%s\n", text);
        fflush(ui->out);
    }
}

void ls_ui_count(ls_ui *ui, ls_gesture g)
{
    if (ui && g >= 0 && g <= LS_GESTURE_HOLD) ui->counts[g]++;
}

/* ---- chart -------------------------------------------------------------- */

/* Draw the trace as a line, not a filled area, for one reason: the threshold
 * rules have to stay visible underneath it. A filled chart hides exactly the
 * information the view is here to show. */
static void draw_chart(ls_ui *ui, int cols, int rows)
{
    int cw = cols - GUTTER;
    if (cw > MAX_COLS) cw = MAX_COLS;
    if (cw < 10) cw = 10;

    int n = ui->count < cw ? ui->count : cw;

    double peak = ui->baseline > 0 ? ui->baseline : 1.0;
    for (int i = 0; i < n; i++) {
        int idx = (ui->head - n + i + MAX_COLS * 2) % MAX_COLS;
        if (ui->ring[idx].lux > peak) peak = ui->ring[idx].lux;
    }
    double ymax = peak * 1.12;
    if (ymax <= 0.0) ymax = 1.0;

    double base    = ui->baseline;
    double release = base * ui->cfg.uncover_ratio;
    double cover   = base * ui->cfg.cover_ratio;

    /* Which row does a lux value land in, 0 = top. */
    #define ROW_OF(v) ((int)(((ymax - (v)) / ymax) * rows))

    /* During calibration there is no baseline yet, so there are no threshold
     * rules to draw. -1 never matches a row. */
    int r_base    = base > 0.0 ? ROW_OF(base)    : -1;
    int r_release = base > 0.0 ? ROW_OF(release) : -1;
    int r_cover   = base > 0.0 ? ROW_OF(cover)   : -1;

    const char *rule = ui->utf8 ? "┄" : "-";
    const char *solid = ui->utf8 ? "─" : "-";

    for (int r = 0; r < rows; r++) {
        /* Left gutter: label the rows that mean something rather than
         * labelling evenly, because the thresholds are the whole point. */
        const char *lbl_col = "";
        char lbl[16];
        if (r == r_base)         { snprintf(lbl, sizeof lbl, "%5.0f", base);    lbl_col = "\033[97m"; }
        else if (r == r_release) { snprintf(lbl, sizeof lbl, "%5.0f", release); lbl_col = "\033[33m"; }
        else if (r == r_cover)   { snprintf(lbl, sizeof lbl, "%5.0f", cover);   lbl_col = "\033[91m"; }
        else if (r == 0)         { snprintf(lbl, sizeof lbl, "%5.0f", ymax);    lbl_col = "\033[90m"; }
        else                       snprintf(lbl, sizeof lbl, "     ");

        sb_addf(ui, "%s%s\033[0m \033[90m%s\033[0m", lbl_col, lbl,
                ui->utf8 ? "│" : "|");

        for (int x = 0; x < cw; x++) {
            int i = n - cw + x;   /* right-align: newest sample at the right */
            if (i < 0) {
                /* No data here yet, but still draw the rules so the
                 * thresholds are legible from the first frame. */
                if (r == r_base)                       sb_addf(ui, "\033[90m%s\033[0m", solid);
                else if (r == r_release)               sb_addf(ui, "\033[33;2m%s\033[0m", rule);
                else if (r == r_cover)                 sb_addf(ui, "\033[31;2m%s\033[0m", rule);
                else                                   sb_add(ui, " ");
                continue;
            }

            int idx  = (ui->head - n + i + MAX_COLS * 2) % MAX_COLS;
            int prev = (idx - 1 + MAX_COLS) % MAX_COLS;
            double v  = ui->ring[idx].lux;
            double pv = (i > 0) ? ui->ring[prev].lux : v;

            double rf = ((ymax - v) / ymax) * rows;
            int    rv = (int)rf;
            if (rv < 0) rv = 0;
            if (rv >= rows) rv = rows - 1;

            int rp = (int)(((ymax - pv) / ymax) * rows);
            if (rp < 0) rp = 0;
            if (rp >= rows) rp = rows - 1;

            if (r == rv) {
                /* Sub-row position picks the block height, which is what
                 * makes a nine-row chart readable at one-lux resolution. */
                double frac = 1.0 - (rf - rv);
                int lvl = (int)(frac * 8.0);
                sb_addf(ui, "%s%s\033[0m", state_colour(ui->ring[idx].state),
                        glyph(ui, lvl));
            } else if ((r > rv && r < rp) || (r < rv && r > rp)) {
                sb_addf(ui, "%s%s\033[0m", state_colour(ui->ring[idx].state),
                        ui->utf8 ? "│" : "|");
            } else if (r == r_base)    sb_addf(ui, "\033[90m%s\033[0m", solid);
            else if (r == r_release)   sb_addf(ui, "\033[33;2m%s\033[0m", rule);
            else if (r == r_cover)     sb_addf(ui, "\033[31;2m%s\033[0m", rule);
            else                       sb_add(ui, " ");
        }
        sb_eol(ui);
    }
    #undef ROW_OF

    /* Axis and time span. */
    sb_add(ui, "      \033[90m");
    sb_add(ui, ui->utf8 ? "└" : "+");
    for (int x = 0; x < cw; x++) sb_add(ui, solid);
    sb_add(ui, "\033[0m");
    sb_eol(ui);

    double span = 0.0;
    if (n > 1) {
        int oldest = (ui->head - n + MAX_COLS * 2) % MAX_COLS;
        span = (ui->t_now - ui->ring[oldest].t) / 1000.0;
    }
    char left[32];
    snprintf(left, sizeof left, "-%.0fs", span);
    sb_addf(ui, "       \033[90m%-*s%s\033[0m", cw - 3, left, "now");
    sb_eol(ui);
}

/* ---- panels ------------------------------------------------------------- */

static void draw_bar(ls_ui *ui, int cols)
{
    int bw = cols - 26;
    if (bw > 60) bw = 60;
    if (bw < 20) bw = 20;

    double r = ui->ratio;
    if (r < 0) r = 0;
    if (r > 1) r = 1;

    int filled  = (int)(r * bw + 0.5);
    int i_cover = (int)(ui->cfg.cover_ratio   * bw + 0.5);
    int i_rel   = (int)(ui->cfg.uncover_ratio * bw + 0.5);

    const char *full = ui->utf8 ? "█" : "#";
    const char *dot  = ui->utf8 ? "·" : ".";
    const char *tick = ui->utf8 ? "│" : "!";

    sb_add(ui, "  signal  ");
    for (int x = 0; x < bw; x++) {
        if (x == i_cover)     sb_addf(ui, "\033[91m%s\033[0m", tick);
        else if (x == i_rel)  sb_addf(ui, "\033[33m%s\033[0m", tick);
        else if (x < filled)  sb_addf(ui, "%s%s\033[0m", state_colour(ui->state), full);
        else                  sb_addf(ui, "\033[90m%s\033[0m", dot);
    }
    sb_addf(ui, "  \033[1m%3.0f%%\033[0m", ui->ratio * 100.0);
    sb_eol(ui);

    /* Label the two ticks underneath so the bar is self-explanatory. Pad up
     * to each marker rather than emitting one space per column: the labels
     * themselves consume columns, and the caret has to land on the tick. */
    char under[256];
    int  cap = (int)sizeof(under) - 16;
    int  p = 0;
    for (int x = 0; x < bw && p < cap; x++) {
        const char *mark = (x == i_cover) ? "^cover"
                         : (x == i_rel)   ? "^release" : NULL;
        if (!mark) continue;
        while (p < x && p < cap) under[p++] = ' ';
        p += snprintf(under + p, sizeof(under) - p, "%s", mark);
    }
    if (p > cap) p = cap;
    under[p] = '\0';
    sb_addf(ui, "  \033[90m        %s\033[0m", under);
    sb_eol(ui);
}

static void draw_status(ls_ui *ui)
{
    const char *sname = ls_state_name(ui->state);

    /* What is the detector waiting for? Naming the pending decision and its
     * countdown is the difference between "it is not working" and "it is
     * working, you have 400 ms left". */
    char pending[80];
    pending[0] = '\0';
    if (ui->state == LS_STATE_COVERED) {
        double left = ui->cfg.hold_ms - (ui->t_now - ui->t_cover_start);
        if (left < 0) left = 0;
        snprintf(pending, sizeof pending, "hold in %.1fs", left / 1000.0);
    } else if (ui->state == LS_STATE_TAP_PENDING) {
        double left = ui->cfg.double_gap_ms - (ui->t_now - ui->t_release);
        if (left < 0) left = 0;
        snprintf(pending, sizeof pending, "tap in %.1fs unless covered again",
                 left / 1000.0);
    } else if (ui->state == LS_STATE_SPENT) {
        snprintf(pending, sizeof pending, "uncover to re-arm");
    }

    sb_addf(ui, "  \033[1m%7.0f\033[0m lux   base \033[90m%.0f\033[0m   "
                "state %s%-13s\033[0m %s",
            ui->lux, ui->baseline, state_colour(ui->state), sname, pending);
    sb_eol(ui);
}

/* Wrap a diagnosis across lines by hand: the messages are long on purpose
 * (they explain a cause, not just a symptom) and a truncated explanation is
 * worse than none. */
static void draw_wrapped(ls_ui *ui, const char *prefix, const char *colour,
                         const char *text, int cols)
{
    int width = cols - 6;
    if (width < 30) width = 30;

    const char *p = text;
    int first = 1;
    while (*p) {
        int take = width;
        int n = (int)strlen(p);
        if (n <= take) take = n;
        else {
            int b = take;
            while (b > 0 && p[b] != ' ') b--;
            if (b > 0) take = b;
        }
        sb_addf(ui, "  %s%s\033[0m %s%.*s\033[0m",
                colour, first ? prefix : " ", colour, take, p);
        sb_eol(ui);
        p += take;
        while (*p == ' ') p++;
        first = 0;
    }
}

static void draw_diag(ls_ui *ui, int cols)
{
    ls_diag_input in;
    in.state            = ui->state;
    in.baseline         = ui->baseline;
    in.ratio            = ui->ratio;
    in.cover_ratio      = ui->cfg.cover_ratio;
    in.uncover_ratio    = ui->cfg.uncover_ratio;
    in.below_release_ms = ui->t_now - ui->t_above_release;
    in.latched_ms       = ui->t_now - ui->t_lux_changed;

    char msg[512];
    ls_diag_level lvl = ls_diag(&in, msg, sizeof msg);

    if (lvl == LS_DIAG_OK) {
        sb_addf(ui, "  \033[32m%s\033[0m \033[90msignal healthy — cover the "
                    "sensor to test\033[0m", ui->utf8 ? "✓" : "ok");
        sb_eol(ui);
        return;
    }
    draw_wrapped(ui,
                 lvl == LS_DIAG_WARN ? (ui->utf8 ? "▲" : "!!")
                                     : (ui->utf8 ? "•" : " *"),
                 lvl == LS_DIAG_WARN ? "\033[33m" : "\033[90m",
                 msg, cols);
}

static void draw_log(ls_ui *ui, int lines)
{
    sb_addf(ui, "  \033[90m%s  \033[0m\033[1m%ld\033[0m\033[90m total\033[0m",
            "GESTURES", (long)ui->logn);
    sb_eol(ui);

    int shown = ui->logn < lines ? ui->logn : lines;
    if (shown == 0) {
        sb_add(ui, "    \033[90m(none yet)\033[0m");
        sb_eol(ui);
    }
    for (int i = 0; i < shown; i++) {
        sb_addf(ui, "    \033[96m%s\033[0m", ui->log[i]);
        sb_eol(ui);
    }
    for (int i = shown; i < lines; i++)
        sb_eol(ui);
}

void ls_ui_render(ls_ui *ui)
{
    if (!ui || !ui->visual || !ui->have) return;

    int cols, rows;
    term_size(ui->out, &cols, &rows);
    if (cols > MAX_COLS + GUTTER) cols = MAX_COLS + GUTTER;
    if (cols < 40) cols = 40;

    /* Everything outside the chart and the log is fixed height: two header
     * lines, four of axis and status, the bar and its legend, the gesture
     * heading, a footer, blanks between them, and up to three lines of
     * diagnosis. Undercount this and the frame is taller than the terminal,
     * which scrolls the header off the top instead of overwriting in place. */
    int fixed = 18;
    int spare = rows - fixed;
    if (spare < 6) spare = 6;

    int chart_rows = spare - LOG_LINES;
    if (chart_rows > MAX_ROWS)  chart_rows = MAX_ROWS;
    if (chart_rows < 4)         chart_rows = 4;

    int log_lines = spare - chart_rows;
    if (log_lines > LOG_LINES)  log_lines = LOG_LINES;
    if (log_lines < 1)          log_lines = 1;

    sb_reset(ui);
    sb_add(ui, "\033[H");

    sb_addf(ui, "  \033[1mlightswitch\033[0m \033[90m%s\033[0m   "
                "\033[90m%s · %s · %.0fs\033[0m",
            "live", ui->source,
            ui->armed ? "\033[91mACTIONS ARMED\033[90m" : "dry run",
            (ui->t_now - ui->t_start) / 1000.0);
    sb_eol(ui);
    sb_addf(ui, "  \033[90mtap %s · double %s · hold %s\033[0m",
            ui->bind[0], ui->bind[1], ui->bind[2]);
    sb_eol(ui);
    sb_eol(ui);

    draw_chart(ui, cols, chart_rows);
    sb_eol(ui);
    draw_status(ui);
    draw_bar(ui, cols);
    sb_eol(ui);
    draw_diag(ui, cols);
    sb_eol(ui);
    draw_log(ui, log_lines);
    sb_eol(ui);
    sb_add(ui, "  \033[90mCtrl-C to stop\033[0m");
    sb_eol(ui);

    sb_add(ui, "\033[J");
    fwrite(ui->sb, 1, ui->sblen, ui->out);
    fflush(ui->out);
}
