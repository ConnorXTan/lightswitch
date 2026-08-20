#include "trace.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>

struct ls_trace_writer {
    FILE *fp;
    int   owns;
};

struct ls_trace_reader {
    FILE *fp;
    int   owns;
    long  line;
};

ls_trace_writer *ls_trace_open_write(const char *path, const char *note,
                                     char *err, size_t errlen)
{
    FILE *fp;
    int owns = 1;

    if (strcmp(path, "-") == 0) {
        fp = stdout;
        owns = 0;
    } else if ((fp = fopen(path, "w")) == NULL) {
        snprintf(err, errlen, "cannot write %s: %s", path, strerror(errno));
        return NULL;
    }

    ls_trace_writer *w = calloc(1, sizeof(*w));
    if (!w) {
        if (owns) fclose(fp);
        snprintf(err, errlen, "out of memory");
        return NULL;
    }
    w->fp = fp;
    w->owns = owns;

    fprintf(fp, "%s\n", LS_TRACE_MAGIC);
    if (note && *note)
        fprintf(fp, "# note: %s\n", note);
    return w;
}

int ls_trace_write(ls_trace_writer *w, double t_ms, double lux)
{
    if (fprintf(w->fp, "%.1f %.2f\n", t_ms, lux) < 0)
        return -1;
    return 0;
}

int ls_trace_close_write(ls_trace_writer *w)
{
    int rc = 0;
    if (!w)
        return 0;
    if (fflush(w->fp) != 0)
        rc = -1;
    if (w->owns && fclose(w->fp) != 0)
        rc = -1;
    free(w);
    return rc;
}

ls_trace_reader *ls_trace_open_read(const char *path, char *err, size_t errlen)
{
    FILE *fp;
    int owns = 1;

    if (strcmp(path, "-") == 0) {
        fp = stdin;
        owns = 0;
    } else if ((fp = fopen(path, "r")) == NULL) {
        snprintf(err, errlen, "cannot read %s: %s", path, strerror(errno));
        return NULL;
    }

    ls_trace_reader *r = calloc(1, sizeof(*r));
    if (!r) {
        if (owns) fclose(fp);
        snprintf(err, errlen, "out of memory");
        return NULL;
    }
    r->fp = fp;
    r->owns = owns;
    return r;
}

int ls_trace_read(ls_trace_reader *r, double *t_ms, double *lux,
                  char *err, size_t errlen)
{
    char line[256];

    while (fgets(line, sizeof(line), r->fp)) {
        r->line++;

        const char *p = line;
        while (*p && isspace((unsigned char)*p))
            p++;
        if (*p == '\0' || *p == '#')
            continue;

        char *end = NULL;
        double t = strtod(p, &end);
        if (end == p) {
            snprintf(err, errlen, "line %ld: expected a timestamp", r->line);
            return -1;
        }
        const char *q = end;
        double v = strtod(q, &end);
        if (end == q) {
            snprintf(err, errlen, "line %ld: expected a lux value", r->line);
            return -1;
        }
        *t_ms = t;
        *lux  = v;
        return 1;
    }
    return 0;
}

void ls_trace_close_read(ls_trace_reader *r)
{
    if (!r)
        return;
    if (r->owns)
        fclose(r->fp);
    free(r);
}
