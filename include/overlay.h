/* overlay.h — the notch glow window.
 *
 * Everything AppKit — the window, the layers, the run loop — is contained
 * entirely in overlay_macos.m: nothing else in the project knows it exists.
 * This header is plain C. The overlay owns the process's main thread (AppKit
 * insists); the sensor/detector poll loop hands it POD ls_glow_input
 * snapshots through ls_overlay_publish and otherwise runs untouched on a
 * worker thread.
 */
#ifndef LS_OVERLAY_H
#define LS_OVERLAY_H

#include "glow.h"

#include <signal.h>
#include <stddef.h>

/* Publish hook for the poll loop (thread-safe; copies the snapshot into a
 * mailbox the renderer reads). wall_ms is ls_now_ms() at publish time so the
 * renderer can extrapolate between ~100 ms samples. */
void ls_overlay_publish(const ls_glow_input *in, double wall_ms);

/* Runs the overlay on the calling (main) thread: spawns a worker thread for
 * poll_main(poll_arg), draws until the worker finishes or *stop is set, then
 * joins the worker. Returns 0, or -1 with a reason in err if the overlay
 * could not start (poll_main is then never called). The poll loop's own exit
 * code stays in poll_arg where the caller put it. Darwin-only symbol. */
int ls_overlay_run(void *(*poll_main)(void *), void *poll_arg,
                   volatile sig_atomic_t *stop, char *err, size_t errlen);

#endif /* LS_OVERLAY_H */
