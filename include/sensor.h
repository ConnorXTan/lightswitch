/* sensor.h — where lux samples come from.
 *
 * Two backends implement one interface:
 *   iokit   the real ambient light sensor (macOS only)
 *   replay  a recorded trace (everywhere, including CI)
 *
 * Everything above this line is platform-independent, so the same detector
 * and the same action dispatch run against live hardware and against fixtures.
 */
#ifndef LS_SENSOR_H
#define LS_SENSOR_H

#include <stddef.h>

typedef struct ls_sensor ls_sensor;

struct ls_sensor {
    const char *kind;
    /* 1 = sample produced, 0 = stream ended, -1 = error. */
    int  (*read)(ls_sensor *s, double *t_ms, double *lux);
    void (*destroy)(ls_sensor *s);
    void *impl;
};

/* Opens the live sensor and paces reads at poll_ms. Returns NULL with a
 * reason in err when there is no sensor or the platform lacks support. */
ls_sensor *ls_sensor_open_iokit(double poll_ms, char *err, size_t errlen);

/* Replays a trace. When realtime is nonzero, sleeps between samples to match
 * the recorded timing; otherwise runs as fast as the file can be read. */
ls_sensor *ls_sensor_open_replay(const char *path, int realtime,
                                 char *err, size_t errlen);

int  ls_sensor_read(ls_sensor *s, double *t_ms, double *lux);
void ls_sensor_close(ls_sensor *s);
const char *ls_sensor_kind(const ls_sensor *s);

/* Milliseconds on a monotonic clock; shared by the backends and main. */
double ls_now_ms(void);
void   ls_sleep_ms(double ms);

#endif /* LS_SENSOR_H */
