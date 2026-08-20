#include "action.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <errno.h>

#ifdef __APPLE__
#include <ApplicationServices/ApplicationServices.h>
#endif

#include <unistd.h>
#include <sys/types.h>

/* macOS virtual keycodes (kVK_* from Carbon's Events.h). The table is plain
 * data, so name lookup is testable on any platform even though only macOS can
 * post the resulting event. */
typedef struct {
    const char    *name;
    unsigned short code;
} key_entry;

static const key_entry KEYS[] = {
    { "a", 0 },  { "b", 11 }, { "c", 8 },  { "d", 2 },  { "e", 14 },
    { "f", 3 },  { "g", 5 },  { "h", 4 },  { "i", 34 }, { "j", 38 },
    { "k", 40 }, { "l", 37 }, { "m", 46 }, { "n", 45 }, { "o", 31 },
    { "p", 35 }, { "q", 12 }, { "r", 15 }, { "s", 1 },  { "t", 17 },
    { "u", 32 }, { "v", 9 },  { "w", 13 }, { "x", 7 },  { "y", 16 },
    { "z", 6 },

    { "0", 29 }, { "1", 18 }, { "2", 19 }, { "3", 20 }, { "4", 21 },
    { "5", 23 }, { "6", 22 }, { "7", 26 }, { "8", 28 }, { "9", 25 },

    { "return", 36 }, { "enter", 36 },  { "tab", 48 },    { "space", 49 },
    { "delete", 51 }, { "escape", 53 }, { "esc", 53 },
    { "left", 123 },  { "right", 124 }, { "down", 125 },  { "up", 126 },
    { "minus", 27 },  { "equal", 24 },  { "grave", 50 },
    { "period", 47 }, { "comma", 43 },  { "slash", 44 },

    { "f1", 122 }, { "f2", 120 }, { "f3", 99 },  { "f4", 118 },
    { "f5", 96 },  { "f6", 97 },  { "f7", 98 },  { "f8", 100 },
    { "f9", 101 }, { "f10", 109 }, { "f11", 103 }, { "f12", 111 },
};

static const size_t NKEYS = sizeof(KEYS) / sizeof(KEYS[0]);

int ls_keycode_for_name(const char *name)
{
    for (size_t i = 0; i < NKEYS; i++) {
        size_t j = 0;
        for (;; j++) {
            unsigned char a = (unsigned char)KEYS[i].name[j];
            unsigned char b = (unsigned char)name[j];
            b = (unsigned char)tolower(b);
            if (a != b)
                break;
            if (a == '\0')
                return (int)KEYS[i].code;
        }
    }
    return -1;
}

const char *ls_key_name_at(size_t index)
{
    return index < NKEYS ? KEYS[index].name : NULL;
}

void ls_action_none(ls_action *a)
{
    memset(a, 0, sizeof(*a));
    a->kind = LS_ACTION_NONE;
    snprintf(a->spec, sizeof(a->spec), "none");
}

static int parse_key_combo(const char *combo, ls_action *out,
                           char *err, size_t errlen)
{
    char buf[128];
    if (strlen(combo) >= sizeof(buf)) {
        snprintf(err, errlen, "key combination is too long");
        return -1;
    }
    snprintf(buf, sizeof(buf), "%s", combo);

    unsigned int mods = 0;
    int          code = -1;
    char        *save = buf;

    for (;;) {
        char *plus = strchr(save, '+');
        if (plus)
            *plus = '\0';

        /* Trim surrounding space so "cmd + w" parses like "cmd+w". */
        char *tok = save;
        while (*tok && isspace((unsigned char)*tok))
            tok++;
        char *end = tok + strlen(tok);
        while (end > tok && isspace((unsigned char)end[-1]))
            *--end = '\0';

        if (*tok == '\0') {
            snprintf(err, errlen, "empty component in key combination");
            return -1;
        }

        if (!strcasecmp(tok, "cmd") || !strcasecmp(tok, "command") ||
            !strcasecmp(tok, "super")) {
            mods |= LS_MOD_CMD;
        } else if (!strcasecmp(tok, "shift")) {
            mods |= LS_MOD_SHIFT;
        } else if (!strcasecmp(tok, "alt") || !strcasecmp(tok, "option") ||
                   !strcasecmp(tok, "opt")) {
            mods |= LS_MOD_ALT;
        } else if (!strcasecmp(tok, "ctrl") || !strcasecmp(tok, "control")) {
            mods |= LS_MOD_CTRL;
        } else {
            if (code >= 0) {
                snprintf(err, errlen,
                         "more than one non-modifier key in combination");
                return -1;
            }
            code = ls_keycode_for_name(tok);
            if (code < 0) {
                snprintf(err, errlen,
                         "unknown key \"%s\" (try --list-keys)", tok);
                return -1;
            }
        }

        if (!plus)
            break;
        save = plus + 1;
    }

    if (code < 0) {
        snprintf(err, errlen, "key combination has no key, only modifiers");
        return -1;
    }

    out->kind      = LS_ACTION_KEY;
    out->keycode   = (unsigned short)code;
    out->modifiers = mods;
    return 0;
}

int ls_action_parse(const char *spec, ls_action *out, char *err, size_t errlen)
{
    memset(out, 0, sizeof(*out));

    while (*spec && isspace((unsigned char)*spec))
        spec++;

    if (strlen(spec) >= LS_ACTION_CMD_MAX) {
        snprintf(err, errlen, "action spec is too long");
        return -1;
    }
    snprintf(out->spec, sizeof(out->spec), "%s", spec);

    if (*spec == '\0' || !strcasecmp(spec, "none") || !strcasecmp(spec, "off")) {
        ls_action_none(out);
        return 0;
    }
    if (!strncasecmp(spec, "key:", 4))
        return parse_key_combo(spec + 4, out, err, errlen);

    if (!strncasecmp(spec, "exec:", 5)) {
        const char *cmd = spec + 5;
        while (*cmd && isspace((unsigned char)*cmd))
            cmd++;
        if (*cmd == '\0') {
            snprintf(err, errlen, "exec: needs a command");
            return -1;
        }
        out->kind = LS_ACTION_EXEC;
        snprintf(out->command, sizeof(out->command), "%s", cmd);
        return 0;
    }

    snprintf(err, errlen,
             "unknown action \"%s\" (expected none, key:..., or exec:...)",
             spec);
    return -1;
}

const char *ls_action_describe(const ls_action *a)
{
    return a->spec[0] ? a->spec : "none";
}

#ifdef __APPLE__
static int run_key(const ls_action *a, char *err, size_t errlen)
{
    CGEventFlags flags = 0;
    if (a->modifiers & LS_MOD_CMD)   flags |= kCGEventFlagMaskCommand;
    if (a->modifiers & LS_MOD_SHIFT) flags |= kCGEventFlagMaskShift;
    if (a->modifiers & LS_MOD_ALT)   flags |= kCGEventFlagMaskAlternate;
    if (a->modifiers & LS_MOD_CTRL)  flags |= kCGEventFlagMaskControl;

    CGEventRef down = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)a->keycode, true);
    CGEventRef up   = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)a->keycode, false);
    if (!down || !up) {
        if (down) CFRelease(down);
        if (up)   CFRelease(up);
        snprintf(err, errlen, "could not create keyboard event");
        return -1;
    }
    CGEventSetFlags(down, flags);
    CGEventSetFlags(up, flags);
    CGEventPost(kCGHIDEventTap, down);
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(down);
    CFRelease(up);
    return 0;
}
#else
static int run_key(const ls_action *a, char *err, size_t errlen)
{
    (void)a;
    snprintf(err, errlen, "key actions require macOS; use exec: instead");
    return -1;
}
#endif

static int run_exec(const ls_action *a, char *err, size_t errlen)
{
    /* Detach so a long-running command cannot stall sampling. SIGCHLD is set
     * to SIG_IGN in main, so the child is reaped by init rather than leaking. */
    pid_t pid = fork();
    if (pid < 0) {
        snprintf(err, errlen, "fork failed: %s", strerror(errno));
        return -1;
    }
    if (pid == 0) {
        setsid();
        execl("/bin/sh", "sh", "-c", a->command, (char *)NULL);
        _exit(127);
    }
    return 0;
}

int ls_action_run(const ls_action *a, char *err, size_t errlen)
{
    switch (a->kind) {
    case LS_ACTION_NONE: return 0;
    case LS_ACTION_KEY:  return run_key(a, err, errlen);
    case LS_ACTION_EXEC: return run_exec(a, err, errlen);
    }
    snprintf(err, errlen, "unknown action kind");
    return -1;
}
