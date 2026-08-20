/* config.h — one key/value namespace shared by the config file and the CLI.
 *
 * Both `--set cover_ratio=0.4` and a `cover_ratio = 0.4` line in the config
 * file funnel through ls_config_set, so the two can never drift apart and the
 * whole surface is testable without touching the filesystem.
 */
#ifndef LS_CONFIG_H
#define LS_CONFIG_H

#include <stddef.h>

#include "action.h"
#include "detector.h"

typedef struct {
    ls_detector_config detector;
    ls_action on_tap;
    ls_action on_double_tap;
    ls_action on_hold;
    double    poll_ms;
} ls_config;

void ls_config_defaults(ls_config *c);

/* Applies one key/value pair. Returns 0, or -1 with a reason in err. */
int ls_config_set(ls_config *c, const char *key, const char *value,
                  char *err, size_t errlen);

/* Applies a "key=value" string (used by --set). */
int ls_config_set_assignment(ls_config *c, const char *assignment,
                             char *err, size_t errlen);

/* Reads a config file. Returns 1 if loaded, 0 if the file does not exist,
 * -1 on a parse or IO error with a reason in err. */
int ls_config_load_file(ls_config *c, const char *path,
                        char *err, size_t errlen);

/* Writes the default config path (~/.config/lightswitch/config) into buf.
 * Returns 0, or -1 if the home directory cannot be determined. */
int ls_config_default_path(char *buf, size_t buflen);

/* True if any gesture is bound to something that would act. */
int ls_config_has_bindings(const ls_config *c);

#endif /* LS_CONFIG_H */
