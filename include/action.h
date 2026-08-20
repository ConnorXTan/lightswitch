/* action.h — what a recognised gesture does.
 *
 * Parsing an action spec is pure string work and lives here so it can be
 * tested anywhere; only ls_action_run needs a platform.
 *
 * Specs:
 *   none                    do nothing (still logged)
 *   key:cmd+w               synthesise a keystroke for the focused app
 *   exec:open -a Finder     run a command line through /bin/sh
 */
#ifndef LS_ACTION_H
#define LS_ACTION_H

#include <stddef.h>

#define LS_MOD_CMD   (1u << 0)
#define LS_MOD_SHIFT (1u << 1)
#define LS_MOD_ALT   (1u << 2)
#define LS_MOD_CTRL  (1u << 3)

#define LS_ACTION_CMD_MAX 512

typedef enum {
    LS_ACTION_NONE = 0,
    LS_ACTION_KEY,
    LS_ACTION_EXEC
} ls_action_kind;

typedef struct {
    ls_action_kind kind;
    unsigned short keycode;   /* platform virtual keycode */
    unsigned int   modifiers; /* LS_MOD_* bitmask         */
    char           spec[LS_ACTION_CMD_MAX];  /* original text, for logging */
    char           command[LS_ACTION_CMD_MAX];
} ls_action;

void ls_action_none(ls_action *a);

/* Returns 0 on success, -1 with a reason in err. */
int  ls_action_parse(const char *spec, ls_action *out, char *err, size_t errlen);

/* Returns 0 on success, -1 with a reason in err (including "unsupported on
 * this platform" for key actions off macOS). */
int  ls_action_run(const ls_action *a, char *err, size_t errlen);

/* Human-readable description, e.g. "key cmd+w" or "none". */
const char *ls_action_describe(const ls_action *a);

/* Look up a key name, returning the virtual keycode or -1. */
int  ls_keycode_for_name(const char *name);

/* Enumerate supported key names for --list-keys; returns NULL past the end. */
const char *ls_key_name_at(size_t index);

#endif /* LS_ACTION_H */
