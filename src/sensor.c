#include "sensor.h"

#include <stddef.h>
#include <time.h>

int ls_sensor_read(ls_sensor *s, double *t_ms, double *lux)
{
    return s->read(s, t_ms, lux);
}

void ls_sensor_close(ls_sensor *s)
{
    if (s)
        s->destroy(s);
}

const char *ls_sensor_kind(const ls_sensor *s)
{
    return s->kind;
}

double ls_now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

void ls_sleep_ms(double ms)
{
    if (ms <= 0.0)
        return;
    struct timespec ts;
    ts.tv_sec  = (time_t)(ms / 1000.0);
    ts.tv_nsec = (long)((ms - (double)ts.tv_sec * 1000.0) * 1e6);
    nanosleep(&ts, NULL);
}
