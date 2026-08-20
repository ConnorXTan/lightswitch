#include "sensor.h"
#include "trace.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    ls_trace_reader *reader;
    int              realtime;
    double           wall0;    /* wall clock when replay started      */
    double           trace0;   /* first timestamp seen in the trace   */
    int              started;
} replay_impl;

static int replay_read(ls_sensor *s, double *t_ms, double *lux)
{
    replay_impl *r = s->impl;
    char err[128];

    int rc = ls_trace_read(r->reader, t_ms, lux, err, sizeof(err));
    if (rc <= 0) {
        if (rc < 0)
            fprintf(stderr, "lightswitch: trace: %s\n", err);
        return rc;
    }

    if (!r->started) {
        r->started = 1;
        r->trace0  = *t_ms;
        r->wall0   = ls_now_ms();
    }
    if (r->realtime) {
        double due     = (*t_ms - r->trace0);
        double elapsed = ls_now_ms() - r->wall0;
        ls_sleep_ms(due - elapsed);
    }
    return 1;
}

static void replay_destroy(ls_sensor *s)
{
    replay_impl *r = s->impl;
    ls_trace_close_read(r->reader);
    free(r);
    free(s);
}

ls_sensor *ls_sensor_open_replay(const char *path, int realtime,
                                 char *err, size_t errlen)
{
    ls_trace_reader *reader = ls_trace_open_read(path, err, errlen);
    if (!reader)
        return NULL;

    ls_sensor   *s = calloc(1, sizeof(*s));
    replay_impl *r = calloc(1, sizeof(*r));
    if (!s || !r) {
        free(s);
        free(r);
        ls_trace_close_read(reader);
        snprintf(err, errlen, "out of memory");
        return NULL;
    }

    r->reader   = reader;
    r->realtime = realtime;

    s->kind    = "replay";
    s->read    = replay_read;
    s->destroy = replay_destroy;
    s->impl    = r;
    return s;
}
