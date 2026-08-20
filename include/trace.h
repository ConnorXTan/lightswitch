/* trace.h — a plain-text recording of the light sensor.
 *
 * A trace is the project's testing backbone: capture a real signal once on
 * real hardware, then replay it forever on any machine. The format is one
 * sample per line so traces diff cleanly in review and can be hand-authored:
 *
 *     # lightswitch trace v1
 *     # note: two taps under office lighting
 *     0.0 4831.0
 *     100.0 4829.5
 *
 * Timestamps are milliseconds from the start of the recording.
 * A lux of -1 records a dropped sensor read.
 */
#ifndef LS_TRACE_H
#define LS_TRACE_H

#include <stddef.h>

#define LS_TRACE_MAGIC "# lightswitch trace v1"

typedef struct ls_trace_writer ls_trace_writer;
typedef struct ls_trace_reader ls_trace_reader;

/* Path "-" writes to stdout. */
ls_trace_writer *ls_trace_open_write(const char *path, const char *note,
                                     char *err, size_t errlen);
int  ls_trace_write(ls_trace_writer *w, double t_ms, double lux);
int  ls_trace_close_write(ls_trace_writer *w);

/* Path "-" reads from stdin. */
ls_trace_reader *ls_trace_open_read(const char *path, char *err, size_t errlen);

/* Returns 1 on a sample, 0 at end of stream, -1 on a malformed line
 * (the reason is written to err and the reader is left usable). */
int  ls_trace_read(ls_trace_reader *r, double *t_ms, double *lux,
                   char *err, size_t errlen);
void ls_trace_close_read(ls_trace_reader *r);

#endif /* LS_TRACE_H */
