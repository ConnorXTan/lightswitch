/* ui.h — live terminal view of the signal and the detector's reasoning.
 *
 * This exists because of a specific failure mode. When a gesture is missed,
 * the cause is almost never "the detector decided wrongly"; it is "the signal
 * never did the thing the detector was waiting for". That is invisible in a
 * log, because the evidence is the gesture that did *not* appear. So the view
 * draws the thresholds alongside the trace, and names the stall when it can
 * see one.
 *
 * The split here mirrors the rest of the project: ls_diag is a pure function
 * of a few numbers and is unit-tested, while the drawing code below it owns
 * all the terminal escapes and is deliberately dumb.
 */
#ifndef LS_UI_H
#define LS_UI_H

#include "detector.h"

#include <stddef.h>
#include <stdio.h>

/* ---- diagnosis (pure) --------------------------------------------------- */

typedef enum {
    LS_DIAG_OK = 0,  /* nothing to say                                       */
    LS_DIAG_NOTE,    /* worth knowing, not currently breaking anything       */
    LS_DIAG_WARN     /* gestures are being missed right now, and here is why */
} ls_diag_level;

typedef struct {
    ls_state state;
    double   baseline;          /* lux                                       */
    double   ratio;             /* last_lux / baseline                       */
    double   cover_ratio;
    double   uncover_ratio;
    double   below_release_ms;  /* time ratio has sat under uncover_ratio    */
    double   latched_ms;        /* time the raw reading has been identical   */
} ls_diag_input;

/* Writes the single most useful sentence about the current signal to msg and
 * returns its severity. Only one message: a panel of six warnings is a panel
 * nobody reads. */
ls_diag_level ls_diag(const ls_diag_input *in, char *msg, size_t len);

/* ---- live view ---------------------------------------------------------- */

typedef struct ls_ui ls_ui;

/* Returns NULL on allocation failure. If out is not a terminal the view falls
 * back to one plain line per gesture, so piping to a file stays readable. */
ls_ui *ls_ui_open(FILE *out, const char *source, int armed);

void ls_ui_binding(ls_ui *ui, ls_gesture g, const char *desc);
void ls_ui_sample(ls_ui *ui, double t_ms, double lux, const ls_detector *d);
void ls_ui_gesture(ls_ui *ui, double t_ms, const char *text);
void ls_ui_count(ls_ui *ui, ls_gesture g);
void ls_ui_render(ls_ui *ui);

/* Restores the terminal and prints the session summary. */
void ls_ui_close(ls_ui *ui);

/* True when drawing full-screen; false when degraded to plain lines. */
int ls_ui_is_visual(const ls_ui *ui);

#endif /* LS_UI_H */
